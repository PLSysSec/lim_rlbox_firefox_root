#!/bin/bash

# reload env variables just in case
if [ -f /etc/profile.d/proxy.sh ]; then
    source /etc/profile.d/proxy.sh
fi

sudo apt -y install git make 

git clone lim/lim_rlbox_firefox_root.git
make -C lim_rlbox_firefox_root setup_guest
