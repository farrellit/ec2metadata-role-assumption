#!/usr/bin/env bash -v
# From http://apple.stackexchange.com/questions/230300/what-is-the-modern-way-to-do-port-forwarding-on-el-capitan-forward-port-80-to
sudo ifconfig lo0 alias 169.254.169.254 255.255.255.255
grep -F '169.254.169.254 localhost' /etc/hosts || echo '169.254.169.254 localhost' | sudo tee -a /etc/hosts
echo "
rdr pass inet proto tcp from any to 169.254.169.254 port 80 -> 127.0.0.1 port 8009
" | sudo pfctl -ef -
