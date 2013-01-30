#!/usr/bin/env perl
use strict;
use warnings;

use IO::Socket;
use IO::Socket::UNIX qw( SOCK_STREAM SOMAXCONN );
#use IO::Socket::Multicast;
use IO::Select;
use Getopt::Long;
use YAML::Syck;
use Data::Dumper;
use File::Temp qw(tempfile);

$| = 1;

# Notes:
# * Possibly make fields configurable per input stream
# * Add some way to reload the config
# * Implement multiple inputs, outputs. Also multiple actions for one set of constraints
# * Allow turning up verbosity for just one input / output / action / transform / linkage, by name
# * Fetch kml.txt from lg-head, fetch KMLs it lists, get their actions.yml
#     (name?) files, and combine them into one config.

our ($verbose_in, $verbose_out, $verbose_link, $verbose_act, $verbose, $kml_server, $help, $fifo)
    = (0, 0, 0, 0, 0, 0, undef);

our @verbose_actions;

sub usage {
    print <<USAGE;

NAME
    viewsyncrelay.pl

SYNOPSIS
    viewsyncrelay.pl [OPTIONS] config_file
    viewsyncrelay.pl --help

DESCRIPTION
    viewsyncrelay accepts Google Earth ViewSync packets as input and,
    optionally, forwards them to one or more destinations, potentially
    transforming them in the process. It is also capable of checking ViewSync
    packets against sets of conditions and starting various actions when the
    conditions are met. 

    viewsyncrelay takes a YAML config file to tell it what to do. See the
    sample config file for an idea of how to use it. It's possible to specify
    multiple config files, or a directory in which all valid YAML files will be
    considered config files.

OPTIONS
    --vi, --vo, --vl, --va, --vt
        Increase verbosity for input streams, output streams, linkages,
        actions, and transforms respectively. Each option can be given more
        than once.
        
    --sva=NAME
        Make action NAME *very* verbose, without getting spam from all the
        other actions

    -f /path/to/fifo, --fifo=/path/to/fifo
        Open (optionally creating first) a FIFO at /path/to/fifo (relative
        paths are acceptable as well) for control commands. This can also be
        specified in the configuration file(s), but the command-line option
        will override the config file. Further documentation is provided in the
        sample config.yml.

    -v, --verbose
        Setting this option once is equivalent to setting --vi, --vo, --vl,
        --va, and --vt. This can be set multiple times

    --kml[=URL]
        Download list of KMLs from a URL (default: http://lg-head/kmls.txt),
        expecting to find a list of KML files therein. It will then download
        each of those KML files, extract actions.yml from each if it exists,
        and use those to configure itself.

    -h, --help
        Print this help

USAGE
}

sub child_action {
    my $pid = fork;
    return $pid if $pid;
    

    my $cmd = shift;
    my $repl = shift;
    my %repl = %$repl;

    # Replace ${KEY} commands in $cmd
    map {
        $cmd =~ s/\$\{$_\}/$repl{$_}/g;
    } keys %repl;

    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '/dev/null' or die "Can't write to /dev/null: $!";

    exec $cmd;
    exit 0;
}

sub parse_constraints {
    # XXX This method of defining constraints kinda sucks. Perhaps there's something better?
    my $cf = shift;
    my $limits;

    for my $constraint (grep { ! /planet/ } (keys %$cf)) {
        my $val = $cf->{$constraint};
        $val =~ s/\s+//g;

        if ($val =~ /(?<min_inc>[\[\(])(?<min>-?[\d\.]+)(?:,(?<max>-?[\d\.]+))?(?<max_inc>[\)\]])/) {
            $limits->{$constraint} = {
                min_inc => ($+{min_inc} eq '['),
                min => $+{min} * 1.0,
                max_inc => ($+{max_inc} eq ']'),
                val => $val,
            };
            $limits->{$constraint}{max} = $+{max} * 1.0 if exists $+{max};
        }
        elsif ($val =~ /(?<center>-?[\d\.]+) \s* \+\/?- \s* (?<range>-?[\d\.]+)/x) {
            # +/- format  "123.4 +- 3"
            $limits->{$constraint} = {
                min_inc => 1,
                max_inc => 1,
                min => ($+{center} - $+{range}),
                max => ($+{center} + $+{range}),
                val => $val
            };
        }
    }
    $limits->{planet} = $cf->{planet} if exists $cf->{planet};
    return $limits;
}

sub match_constraints {
    my ($name, $msg, $limits) = @_;
    my %msg_vals;
    my @fields = qw/count latitude longitude altitude heading tilt roll start_time end_time planet/;
    my $do_action = 1;
    @msg_vals{@fields} = split(',', $msg);
    my $result = {
        'pass' => [],
    };

    eval {
        map {
            my $field = $_;
            my $val = $msg_vals{$field};

            if (exists $limits->{$field} && defined $limits->{$field}) {
                if (
                    ($val > $limits->{$field}{min} &&
                        (exists $limits->{$field}{max} && $val < $limits->{$field}{max})
                    ) ||
                    ($limits->{$field}{min_inc} && $val == $limits->{$field}{min})
                ) {
                    push(@{$result->{pass}}, $field);
                }
                else {
                    $result->{fail} = $field;
                    $result->{failed_constraints} = $limits->{$field}{val};
                    $result->{failed_value} = $val;
                    $do_action = 0;
                    die;
                }
            }

        } grep { $_ ne 'planet' } @fields;
                # ^^ these constraints are only designed to handle numeric
                # values, so don't bother with a non-numeric field

        # For now, assume you'll only ever want an action to work for one
        # single planet, so there's no support for sets of planets
        $msg_vals{planet} = 'earth' if (! defined $msg_vals{planet});
        if (exists $limits->{planet}) {
            if (lc($msg_vals{planet}) eq lc($limits->{planet})) {
                push @{$result->{pass}}, 'planet';
            }
            else {
                $result->{fail} = 'planet';
                $result->{failed_constraints} = $limits->{planet};
                $result->{failed_value} = $msg_vals{planet};
                $do_action = 0;
                die;
            }
        }
    };
    return [$do_action, $result, \%msg_vals];
}

sub run_action {
    my $name = shift;
    my $config = shift;
    my $cmds = shift;

    my ($last_fail, $fail_count) = (0, 0);
    my $tour_started = ! exists $config->{tour_name};

    if (exists $config->{verbose}) {
        $verbose_act = $config->{verbose};
    }

    if (exists $config->{id}) {
        my @a = grep { $_ eq $config->{id} } @verbose_actions;
        $verbose_act += $#a if $#a >= 0;
    }

    print "Action $name disabled waiting for tour $config->{tour_name} to start\n"
        if ($verbose_act > 1 && exists $config->{tour_name});

    my ($limits, $reset_limits);
    my $repeat = $config->{repeat} || 'DEFAULT';
    $repeat = uc $repeat;

    # Set up config
    $limits = parse_constraints($config->{constraints});
    $reset_limits = parse_constraints($config->{reset_constraints}) if exists $config->{reset_constraints};
    print "Action $name constraints: " . Dumper($limits) if $verbose_act > 2;
    print "Action $name reset_constraints: " . Dumper($reset_limits) if $verbose_act > 2;

    my $run_next = 1;
    if ($config->{initially_disabled}) {
        print "Disabling action $name at startup\n" if $verbose_act;
        $run_next = 0;
    }
    my $running = 0;
    my $pid;

    STDIN:
    while (<STDIN>) {
        chomp;
        exit 0 if /^EXIT$/;
        next if /^$/;
        my $msg = $_;
        print "Action \"$name\" received $msg\n" if $verbose_act > 3;

        if ($msg =~ /CONTROL:\W/) {
            # Handle tour control commands
            if ($msg =~ /\Wstarttour (.*)$/) {
                if (exists $config->{tour_name} && $config->{tour_name} eq $1) {
                    print "Enabling action $config->{id} as part of starting tour $config->{tour_name}\n"
                        if ($verbose_act >= 1);
                    $tour_started = 1;
                }
            }
            elsif ($msg =~ /\Wexittour/) {
                print "Disabling action $config->{id} with exit of tour\n"
                    if ($verbose_act > 1 && exists $config->{tour_name});
                $tour_started = 0;
                $run_next = !($config->{initially_disabled});
                $running = 0;
                # XXX Make this work
                system "kill -9 $pid" if $pid;
            }
            else {
                print "Didn't recognize control message \"$msg\"\n";
            }
            next STDIN;
        }

        next STDIN unless $tour_started;
        
        my $do_action = 1;

        my $res = match_constraints($name, $msg, $limits);
        my $matches = $res->[0];
        if ($run_next && $verbose_act > 2 && !$matches) {
            $fail_count++;
            # Only print out every 15th failure, unless the last viewsync packet matched
            if (! $last_fail || $fail_count >= 15) {
                print "Failed check on action $name: " . Dumper($res->[1]);
                $fail_count = 0;
            }
            $last_fail = 1;
        }
        if ($run_next && $matches) {
            $run_next = 0 unless $repeat eq 'ALL';
            print "Action $name ($config->{action}) is going to be run now (repeat mode: $repeat): " . Dumper($res->[2]) . "\n" if $verbose_act;
            $pid = child_action($config->{action}, $cmds);
            $running = 1;
        }
        else {
            if ($running && !$matches && exists $config->{exit_action}) {
                print "Running exit_action for $name: $config->{exit_action}\n"
                    if ($verbose_act > 0 && exists($config->{exit_action}) && defined($config->{exit_action}));
                $pid = child_action($config->{exit_action}, $cmds);
                $running = 0;
            }
            if ($repeat ne 'ONCE' && $repeat ne 'RESET' && !$matches) {
                print "Resetting action $name because of failed test on field\n"
                    if ($run_next == 0 and $verbose_act > 0);
                $run_next = 1;
            }
        };

        if ($repeat eq 'RESET') {
            if ($run_next == 0) {
                my $res2 = match_constraints("$name [RESET]", $msg, $reset_limits);
                if ($res2->[0]) {
                    print "Resetting RESET action $name.\n" if $verbose_act;
                    $run_next = 1;
                }
                else {
                    if ($verbose_act > 1 && ! $run_next) {
                        $fail_count++;
                        # Only print out every 15th failure, unless the last viewsync packet matched
                        if (! $last_fail || (exists $config->{fail_count} && $fail_count > $config->{fail_count}) || $fail_count >= 15) {
                            print "Not resetting RESET action $name because of failed test: " . Dumper($res2->[1]);
                            $fail_count = 0;
                        }
                        $last_fail = 1;
                    }

                }
            }
        }
    }
}

sub run_linkage {
    my $name = shift;
    my $output_pipe = shift;

    # XXX See if we have a transform to do, and figure out how to implement them.
    while (<STDIN>) {
        chomp;
        exit 0 if /^EXIT$/;
        print "Linkage \"$name\" received $_\n" if $verbose_link > 1;
        next if /^CONTROL:/;
        print $output_pipe "$_\n";
    }
}

sub run_output {
    my ($name, $host, $port, $broadcast) = @_;

    my $socket = IO::Socket::INET->new(
        PeerAddr=> $host,
        PeerPort => $port,
        Proto => 'udp',
        Broadcast => $broadcast
    ) or die "Failed to create UDP socket for output stream \"$name\": $@";
    $socket->autoflush();

    while (<STDIN>) {
        chomp;
        exit 0 if /^EXIT$/;
        print "Output stream \"$name\" received $_\n" if $verbose_out > 1;
        print $socket "$_";
        #print $socket "$_\n";
        $socket->flush();
    }
}

sub open_child {
    my $name = shift;
    my $sub = shift;
    my @args = @_;
    my $sleep_count = 0;
    my ($kid_pid, $kid_pipe);
    do {
        $kid_pid = open($kid_pipe, '|-');
        unless (defined $kid_pid) {
            warn "cannot fork child process \"$name\": $!";
            die "...therefore we're dying here." if $sleep_count++ > 6;
            sleep 5;
        }
    } until (defined $kid_pid);
    if ($kid_pid == 0) {
        $0 = $name;
        $SIG{INT} = 'DEFAULT';
        $sub->(@args);
        exit 0;
    }

    return ($kid_pid, $kid_pipe);
}

sub build_input_streams {
    my %input_streams;
    my $config = shift;
    my $select = shift;
    for my $stream (@{$config->{input_streams}}) {
        my $localAddr = $stream->{addr} || '0.0.0.0';
        my $port = $stream->{port};
        my $name = $stream->{name};
        print STDERR "Opening listen socket on $localAddr:$stream->{port}\n" if $verbose_in > 0;
        my $r = IO::Socket::INET->new(
            LocalPort => $stream->{port},
            LocalAddr => $localAddr,
            Proto => 'udp'
        ) or die "Couldn't set up receiving socket (UDP, $localAddr:$port): $@";
        $$r->{viewsyncrelay_name} = $name;
        @{$input_streams{$name}}{qw/HANDLE ADDR PORT DO_COUNTER PEER_ADDR PEER_PORT COUNTER/} = ( $r, $localAddr, $port, 0, undef, undef, 0 );
        $select->add($r);
    }
    return \%input_streams;
}

sub build_output_streams {
    my %output_streams;
    my $config = shift;

    for my $stream (@{$config->{output_streams}}) {
        my ($name, $host, $port) = 
            map {
                die "Each output stream must have a name, host, and port. Missing a $_"
                    unless exists $stream->{$_};
                $stream->{$_};
            } qw/name host port/;
        my $broadcast = 0;
        $broadcast = 1 if (exists $stream->{broadcast} && lc $stream->{broadcast} eq 'true');
        my ($kid_pid, $kid_pipe) = open_child(
                "Output stream \"$name\"",
                \&run_output,
                ($name, $host, $port, $broadcast)
        );
        $kid_pipe->autoflush();
        $output_streams{$name}{PID} = $kid_pid;
        $output_streams{$name}{STDIN} = $kid_pipe;
    }
    return \%output_streams;
}

sub build_linkages {
    my %linkages;
    my $config = shift;
    my $output_streams = shift;

    for my $linkage (@{$config->{linkages}}) {
        my ($name, $input, $output) = 
            map {
                die "Each linkage must have a name, input, and output. Missing a $_"
                    unless exists $linkage->{$_};
                $linkage->{$_};
            } qw/name input output/;
        my $output_pipe = $output_streams->{$output}{STDIN};
        die "Couldn't find output stream \"$output\"!" unless defined $output_pipe;
        my ($link_pid, $link_pipe) = open_child(
            "Linkage \"$name\"",
            \&run_linkage,
            ( $name, $output_pipe )
        );
        $link_pipe->autoflush();
        @{$linkages{$name}}{qw/OUTPIPE NAME INPUT PID STDIN/} =
            ( $output_pipe, $name, $input, $link_pid, $link_pipe );
    }
    return \%linkages;
}

sub build_actions {
    my %actions;
    my $config = shift;
    my $cmds = (exists $config->{action_commands} ? $config->{action_commands} : undef);
    for my $action (@{$config->{actions}}) {
        print Dumper($action) if $verbose_act > 2;
        my ($name, $input, $constraints) = 
            map {
                die "Each action must have a name, input, and constraints. Missing a $_ (" . Dumper($action) . ")"
                    unless exists $action->{$_};
                $action->{$_};
            } qw/name input constraints/;
        my ($action_pid, $action_pipe) = open_child( "Action \"$name\"", \&run_action, ( $name, $action, $cmds ));
        $action_pipe->autoflush();
        @{$actions{$name}}{qw/NAME INPUT PID STDIN/} = ( $name, $input, $action_pid, $action_pipe );
        $actions{$name}{initially_disabled} = 1 if exists $action->{initially_disabled};
    }
    return \%actions;
}

sub load_config_file {
    my $config = shift;
    my $file_name = shift;
    my $file;

    eval {
        $file = YAML::Syck::LoadFile $file_name;
    };

    die $@ if $@;

    map {
        my @a = @{$config->{$_}};
        if (defined $file->{$_} && exists $file->{$_}) {
            @a = (@{$config->{$_}}, @{$file->{$_}})
        }
        else {
            @a = @{$config->{$_}};
        }
        $config->{$_} = \@a;
    } qw/input_streams output_streams transformations linkages actions/;

    my %file_ac = exists $file->{action_commands} ? %{$file->{action_commands}} : ();
    my %config_ac = exists $config->{action_commands} ? %{$config->{action_commands}} : ();
    @config_ac{keys %file_ac} = values %file_ac;
    $config->{action_commands} = \%config_ac;

    # Copy an action's constraints to the next action's reset_constraints if
    #   1) the next action has a RESET repeat configuration
    #   2) the next action doesn't already have its own reset_constraints
    # Also, disable all but the first action, unless otherwise specified

    my @actions = @{$config->{actions}};
    if ($#actions > -1) {
        my $prev_reset = $actions[$#actions]->{constraints};
        my $first = 1;
        map {
            $_->{repeat} = 'DEFAULT' unless exists $_->{repeat};
            if ($_->{repeat} eq 'RESET' and ! exists $_->{reset_constraints}) {
                $_->{reset_constraints} = $prev_reset;
                if (!$first) {
                    $_->{initially_disabled} = 1 unless exists $_->{initially_disabled};
                }
            }
            $first = 0;
            $prev_reset = $_->{constraints};
        } @{$config->{actions}};
    }
}

sub load_config {
    my $downloaded_config = shift;
    my %config_values = (
        input_streams => [],
        output_streams => [],
        transformations => [],
        linkages => [],
        actions => [],
        action_commands => {}
    );

    if ($downloaded_config) {
        my $tmp = YAML::Syck::Load($downloaded_config);
        map {
            push @{$config_values{$_}}, $tmp->{$_};
        } qw/input_streams output_streams actions transformations linkages action_commands/;
    }

    for my $file (@ARGV) {
        if (-d $file) {
            opendir(my $dh, $file) || die "Can't opendir $file: $!";
            map {
                load_config_file \%config_values, "$file/$_";
            } grep { (! /^\./) && -f "$file/$_" } readdir($dh);
            closedir $dh;
        }
        elsif (-f $file) {
            load_config_file \%config_values, $file;
        }
    }
    return \%config_values;
}

sub reconstruct_viewsync {
    push @_, ''
        while ($#_ < 9);
    return join(',', @_);
}

## MAIN PROGRAM BEGINS HERE

GetOptions(
    "--vi+" => \$verbose_in,
    "--vo+" => \$verbose_out,
    "--vl+" => \$verbose_link,
    "--va+" => \$verbose_act,
    "--sva=s" => \@verbose_actions,
    "--verbose+" => \$verbose,
    "--kml:s" => \$kml_server,
    "--fifo:s" => \$fifo,
    "--help" => \$help
);

my $downloaded_config = '';
if ($kml_server) {
    $kml_server = 'http://lg-head/kmls.txt' if $kml_server eq '';

    # Using curl here rather than pure Perl beceause I don't want to add a
    # requirement for some Perl module. Perhaps that's silly of me.
    my @kmls = split( /\n/, qx/curl $kml_server/ );
    for my $kml (grep { /\.kmz/ } @kmls) {
        $kml =~ s/lg-head/localhost:8081/;
        print "Trying $kml...\n";
        my ($fh, $filename) = tempfile();
        close $fh;
        qx{curl $kml > $filename};
        $downloaded_config .= qx{unzip -c -qq $filename actions.yml}; 
        unlink $filename;
    }

    die "Collected actions: $downloaded_config\n";
}

$verbose_in   += $verbose;
$verbose_out  += $verbose;
$verbose_link += $verbose;
$verbose_act  += $verbose;

if ($help) {
    usage();
    exit 1;
}

my $config = load_config($downloaded_config);
my $select = IO::Select->new;

my %input_streams = %{ build_input_streams($config, $select) };
if (exists $config->{control} || defined $fifo) {
    use IO::Socket::UNIX;

    $verbose && print "Opening FIFO $fifo\n";
    $fifo ||= $config->{control};
    my $r = IO::Socket::UNIX->new(
        Type => SOCK_DGRAM,
        LocalAddr => $fifo,
        Listen => SOMAXCONN
    ) or die "Couldn't set up control FIFO ($fifo): $@";
    $$r->{vsr_control} = 1;
    $select->add($r);
}
my %output_streams = %{ build_output_streams $config };
my %linkages = %{ build_linkages($config, \%output_streams) };
my %actions = %{ build_actions $config };

$SIG{INT} = sub {
    print "Received interrupt signal.\n" if $verbose > 0;
    map {
        my $hash = $_;
        map {
            print { $hash->{$_}{STDIN} } "EXIT\n";
        } ( keys %$hash );
    } ( \%output_streams, \%linkages, \%actions );
    exit 0;
};

$| = 1;

my $do_counter = 0;

while (1) {
    my @handles = $select->can_read(0.5);
    if ($#handles >= 0) {
        HANDLE: for my $a (@handles) {
            my $msg;
            $a->recv($msg, 1024);
            my ($input_stream_name, $control_fifo) = (undef, 0);
            if (exists $$a->{vsr_control}) {
                # This comes from the control FIFO
                print "Control FIFO received $msg\n" if $verbose_in > 1;
                $msg = 'CONTROL:\t' . $msg;
                $control_fifo = 1;
            }
            else {
                print "Input stream \"$$a->{viewsyncrelay_name}\" received $msg\n" if $verbose_in > 1;
                $input_stream_name = $$a->{viewsyncrelay_name};

                if ($msg !~ /^CONTROL:/) {
                    my @viewsync = split(',', $msg);
                    my ($peer_port, $peer_addr) = sockaddr_in($a->peername);

                    if (!defined $input_streams{$input_stream_name}{PEER_ADDR}) {
                        @{ $input_streams{$input_stream_name} }{qw/PEER_ADDR PEER_PORT COUNTER/} = ( $peer_addr, $peer_port, $viewsync[0] );
                    }
                    elsif ($input_streams{$input_stream_name}{DO_COUNTER}) {
                        $viewsync[0] = ++$input_streams{$input_stream_name}{COUNTER};
                        $msg = reconstruct_viewsync(@viewsync);
                    }
                    else {
                        if ($viewsync[0] > $input_streams{$input_stream_name}{COUNTER}) { 
                            $input_streams{$input_stream_name}{COUNTER} = $viewsync[0];
                        }
                        else {
                            # Do we take control?
                            print "View Counter has not increased. internal counter=$input_streams{$input_stream_name}{COUNTER}, recvd view_counter=$viewsync[0]\n" if $verbose_in > 0;

                            # Has viewmaster host changed?
                            if ($peer_addr eq $input_streams{$input_stream_name}{PEER_ADDR}) {
                                print "View Master IP address is same as old, taking control of View Counter.\n" if $verbose_in > 0;
                                $input_streams{$input_stream_name}{DO_COUNTER} = 1;
                                $viewsync[0] = ++$input_streams{$input_stream_name}{COUNTER};
                                $msg = reconstruct_viewsync(@viewsync);
                            } else {
                                print "View Master IP address has changed from ". inet_ntoa($input_streams{$input_stream_name}{PEER_ADDR}) ." to ". inet_ntoa($peer_addr) . ". Exiting.\n";
                                exit(0);
                            }
                        }
                    }
                }
            }

            # Send this message to each linkage and action registered to
            # receive input from this stream
            map {
                my $hash = $_;
                map {
                    my $key = $_;
                    print { $hash->{$key}{STDIN} } "$msg\n"
                        if ($hash->{$key}{INPUT} eq 'ALL' || 
                            $control_fifo ||
                            $hash->{$key}{INPUT} eq $input_stream_name);
                } ( keys %$hash );
            } ( \%linkages, \%actions );
        }
    }
}
