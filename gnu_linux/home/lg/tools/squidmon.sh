#!/bin/bash

## GET CMDs
# wget -q -t 1 -T 6 -O /dev/null --header='Host: www.endpoint.com' $SOMEFILE
# curl -o /dev/null --no-keepalive -f -s -m 6 --retry 0 --header 'Host: www.endpoint.com' $SOMEFILE

. ${HOME}/etc/shell.conf
smallfile="http://www.endpoint.com/robots.txt"
stampfile="/tmp/squidstamp"
sqpidfile="/var/run/squid3.pid"

(echo -n "$0 Start: "; date) | logger -p local3.info

# only run on the master system
if [[ ${FRAME_NO:-1} -ne 0 ]]; then
    echo "$0: not master system. Exiting." | logger -p local3.err
    exit 1
fi

while :; do
    2>&1 /home/lg/bin/lg-run "\
    touch -t \"\$( date --date='5 minutes ago' +%y%m%d%H%M.%S )\" $stampfile;
    if [[ -n \"\$( pgrep -f 'sbin\/squid3' )\" ]]; then
        if ( wget -q -t 1 -T 6 -O /dev/null --header='Host: www.endpoint.com' \"$smallfile\" ); then
            logger -p local3.info \".squidok.\";
        elif [[ $sqpidfile -nt $stampfile ]]; then
            logger -p local3.info \".waiting for squid to age.\";
        else
            logger -p local3.err \"\$(date +%s).\$(hostname).squidrestart.\";
            ssh -i ~/.ssh/lg-id_rsa root@localhost \"service squid3 restart\" | logger -p local3.info;
        fi
    else
        logger -p local3.err \"\$(date +%s).\$(hostname).squidrestart.\";
        ssh -i ~/.ssh/lg-id_rsa root@localhost \"service squid3 restart\" | logger -p local3.info;
    fi
    " >/dev/null
    sleep 6
done
