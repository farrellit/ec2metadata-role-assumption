#!/usr/bin/env bash -v
sudo ifconfig lo0 alias 169.254.169.254 255.255.255.255
# if you had ipfw or iptables, you wouldn't have to sudo the 
# exec to open port 80.
# sudo ipfw add 100 fwd 127.00.1,65001 tcp from any to any 80 in
