#!/bin/bash

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

if which "docker.exe" > /dev/null 2>&1; then
  dockercmd="docker.exe"
else
  dockercmd="docker"
fi

$sudo $dockercmd run --name ec2metadata -e RACK_ENV=${RACK_ENV:-production}\
  ${args:---rm -d} -p $LOCALIP:80:4567 \
  -v `ls -d ${AWS_PROFILE_PATH:-~/.aws}`:/root/.aws \
  -e MYNAME \
  ${image:-farrellit/ec2metadata:latest}
