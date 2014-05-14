#!env ruby

# :stopdoc:

# The idea here is to ingest one tour from one KML document, and make it
# multicamera-ish

#require 'rubygems'
$LOAD_PATH << './lib'
require 'bundler/setup'
require 'kamelopard'
require 'libxml'

# command line options: a single kml file. Prints KML to stdout

def process_wait(w)
    Kamelopard::Wait.parse(w)
end

def process_flyto(f)
    # The idea here is to check the flytomode. If it's "smooth", just fly to
    # that point. If it's "bounce", use bounce() to simulate the flyto. Since
    # bounce() requires a start and an end, we'll need to keep track of where
    # we are, so if the next flyto is a bounce, we have a start point.
    # XXX Question: What if the *first* flyto is a bounce? We won't have a
    # start point. Throw an error?
    # XXX Should we assume a default value for flyToMode, if we don't find one?
    f.find('//gx:flyToMode').each do |m|
        if m.children[0].to_s == 'smooth'
        break
    end
end

d = XML::Document.file(ARGV[0])
tours = d.find('//gx:Tour')
if tours.size > 1 then
    STDERR.puts "Found multiple tours in this document. Processing only the first."
    # XXX Fix this
elsif tours.size == 0 then
    STDERR.puts "Found no tours in the document. Error."
    exit 1
end

tour = tours[0]

tour.find('//gx:FlyTo|//gx:Wait').each do |n|
    if n.name == 'Wait'
        Kamelopard::Wait.parse(w)
    elsif n.name == 'FlyTo'
        process_flyto n
    end
end

puts get_kml.to_s
