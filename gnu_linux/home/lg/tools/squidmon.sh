#!/bin/bash

. ${HOME}/etc/shell.conf
smallfile="http://www.endpoint.com/robots.txt"

(echo -n "squidmon Start: "; date)>>/home/lg/tmp/squidmon.log

# only run on the master system
if [[ ${FRAME_NO:-1} -ne 0 ]]; then
    echo "not master system. Exiting." >>/home/lg/tmp/squidmon.log
    exit 1
fi

while :; do
    /home/lg/bin/lg-run "\
    if [[ -n \"\$( pgrep -f 'sbin\/squid3' )\" ]] \
    && ( wget -q -t 1 -T 6 -O /dev/null --header='Host: www.endpoint.com' \"$smallfile\" ); then
        echo -n \".squidok.\";
     else
     date >&2
        echo \"\$(hostname).squidrestart.\" >&2;
        ssh -i ~/.ssh/lg-id_rsa root@localhost service squid3 restart;
     fi
    " 2>>/home/lg/tmp/squidmon.log
    sleep 6
done
