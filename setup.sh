#!/bin/bash

LOCALIP='169.254.169.254'
OS=$(uname -s)

# not sure if this is really required or a good idea
# grep -F "$LOCALIP localhost" /etc/hosts || echo "$LOCALIP localhost" | sudo tee -a /etc/hosts

if [ "$OS" == "Darwin" ] ; then
  # From http://apple.stackexchange.com/questions/230300/what-is-the-modern-way-to-do-port-forwarding-on-el-capitan-forward-port-80-to

  # This creates a local device on $LOCALIP
  sudo ifconfig lo0 alias $LOCALIP 255.255.255.255

  echo "
  rdr pass on lo0 inet proto tcp from (lo0) to $LOCALIP port 80 -> 127.0.0.1 port 8009
  " | sudo pfctl -ef -

elif [ "$OS" == "Linux" ] ; then
  sudo ip address add $LOCALIP/32 label lo:0 dev lo
  sudo iptables -t nat -I OUTPUT --src localhost --dst $LOCALIP -p tcp --dport 80 -j REDIRECT --to-ports 8009
else
  echo "OS Not detected correctly"
  exit 1
fi
