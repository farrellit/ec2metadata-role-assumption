#!/bin/sh 

MYNAME=`whoami`@`hostname`

LOCALIP='169.254.169.254'

if [ "`id -u`" == "0" ]; then
  sudo=""
else
  sudo="sudo"
fi

if $sudo which ip; then 
  # todo: what if lo:0 is in use?  Shouldn't we check?  is there an automatic way?
  $sudo ip address add $LOCALIP/32 label lo:0 dev lo
elif $sudo which ifconfig; then 
  $sudo ifconfig lo0 alias $LOCALIP 255.255.255.255
else
  echo "IP Configuration utility not detected correctly"
  exit 1
fi
# this docker runs on 80 and will have to be sudoed
# better than a redirect, I believe.

$sudo docker run --name ec2metadata -e RACK_ENV=production \
  --rm -d -p 169.254.169.254:80:4567 \
  -v `ls -d ~.aws`:/root/.aws \
  -e MYNAME \
  farrellit/ec2metadata:latest 
