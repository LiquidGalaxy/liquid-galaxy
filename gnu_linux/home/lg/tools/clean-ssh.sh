#!/bin/bash
# Copyright 2010 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# !!! THIS SHOULD REALLY ONLY BE EXECUTED ON 
# A SINGLE SYSTEM _BEFORE_ CLONING !!!
# 
# Tue Jul 20 13:55:14 EDT 2010
# - Kiel C <kiel@endpoint.com>
#

# the lg systems should allow ssh between them
LG_KEY=${HOME}/.ssh/lg-id_rsa
LG_PUBKEY=${LG_KEY}.pub
AUTH_KEYS=${HOME}/.ssh/authorized_keys
KNOWN_HOSTS=/etc/ssh/ssh_known_hosts

# exit now if we do not have sudo functionality
if ( sudo ls / >/dev/null ); then
    echo "sudo ok..."
else
    echo "You need sudo privileges to do complete this."
    exit 3
fi

if [[ -r $LG_PUBKEY ]]; then
    echo -n "Do you want to re-generate and destroy \"${LG_PUBKEY}\", host keys, and known_hosts files? [y/N]: "
    read regenyn
fi

if [[ ! -r $LG_PUBKEY ]] || [[ "$regenyn" = "y" ]]; then
    echo "generating new keypairs"
    ssh-keygen -t rsa -b 4096 -C "Liquid Galaxy" -f $LG_KEY
    # re-generate host keys to pave the way
    sudo rm -vf /etc/ssh/ssh_host_???_key*
    sudo dpkg-reconfigure openssh-server
else
    echo "using existing keypairs"
fi

# destroy global known_hosts to pave the way
sudo sh -c "echo -n '' > $KNOWN_HOSTS" || exit 1
host_pubrsa=$( awk '{print $1 " " $2}' /etc/ssh/ssh_host_rsa_key.pub )

# first "localhost"
sudo sh -c "echo \"localhost,lgX,127.0.0.1 $host_pubrsa\" >> $KNOWN_HOSTS"
# then lg list
for sys in `seq 1 8`; do
    sudo sh -c "echo \"lg${sys},10.42.42.$sys $host_pubrsa\" >> $KNOWN_HOSTS"
done

# ensure permissions and dir/file exists using safe operations
mkdir -p ${HOME}/.ssh
chmod 0700 ${HOME}/.ssh
touch $AUTH_KEYS
chmod 0600 $AUTH_KEYS

# overwrite local authorized_keys
cat $LG_PUBKEY > $AUTH_KEYS

# NOW FOR ROOT
sudo mkdir -p /root/.ssh
sudo chmod 0700 /root/.ssh
sudo touch /root/.ssh/authorized_keys
sudo chmod 0600 /root/.ssh/authorized_keys

# overwrite root authorized_keys
sudo sh -c "cat $LG_PUBKEY > /root/.ssh/authorized_keys"

echo "all done: make sure to also setup \"${HOME}/.ssh/config\".
You may also want to add some of your own keys."

exit 0
