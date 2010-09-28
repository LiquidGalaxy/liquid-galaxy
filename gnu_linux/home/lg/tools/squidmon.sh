#!/bin/bash

(echo -n "squidmon Start: "; date)>>/home/lg/tmp/squidmon.log

while :; do
    /home/lg/bin/lg-run "\
    if [[ -n \"\$( pgrep -f 'sbin\/squid3' )\" ]]; then
        echo -n \".squidok.\";
     else
     date >&2
        echo \"\$(hostname).squidrestart.\" >&2;
        ssh -i ~/.ssh/lg-id_rsa root@localhost service squid3 restart;
     fi
    " 2>>/home/lg/tmp/squidmon.log
    sleep 6
done
