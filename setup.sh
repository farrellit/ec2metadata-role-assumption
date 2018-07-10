#!/bin/bash

MYNAME=`whoami`@`hostname`

DOCKERNETNAME='ec2metadata'
# Using a /30 here only allows 169.254.169.254 available.
DOCKERNET='169.254.169.252/30'
DOCKERGATEWAY='169.254.169.253'

if [ "`id -u`" == "0" ]; then
  sudo=""
else
  sudo="sudo"
fi

if which "docker.exe" > /dev/null 2>&1; then
  dockercmd="docker.exe"
else
  dockercmd="docker"
fi


# we might need to remove 169.254.169.254 from lo, 
# added by older versions
if $sudo which ifconfig; then 
  # mac uses lo0, maybe other bsds too?
  if $sudo ifconfig lo0 > /dev/null 2>&1; then 
    interface=lo0
  else
    interface=lo
  fi
  if $sudo ifconfig $interface | grep -qF 169.254.169.254; then
    $sudo ifconfig $interface delete 169.254.169.254
  fi
elif $sudo which ip; then 
  # some people do have `ip` on osx, it turns out, maybe others too
  if $sudo ip show dev lo0 | grep -q -F 169.254.169.254; then
    interface=lo0
  else
    interface=lo
  fi
  $sudo ip addr del 169.254.169.254 dev lo0
fi 

# use a docker net -  then we can be OSagnostic.

$dockercmd network inspect $DOCKERNETNAME &> /dev/null
if [[ $? != 0 ]] ; then
  $dockercmd network create \
    --gateway $DOCKERGATEWAY \
    --subnet $DOCKERNET \
    -o com.docker.network.bridge.enable_icc=true \
    -o com.docker.network.bridge.enable_ip_masquerade=true \
    -o com.docker.network.bridge.host_binding_ipv4=0.0.0.0 \
    -o com.docker.network.bridge.name=$DOCKERNETNAME \
    -o com.docker.network.driver.mtu=1500 \
    $DOCKERNETNAME
fi

if [ -z ${image+x} ]; then 
  $dockercmd pull farrellit/ec2metadata:latest
fi 

$dockercmd run \
  --name ec2metadata \
  -e RACK_ENV=${RACK_ENV:-production} \
  --network $DOCKERNETNAME \
  -p 80:80 \
  -v `ls -d ${AWS_PROFILE_PATH:-~/.aws}`:/root/.aws \
  -e MYNAME \
  ${args:---rm -d} \
  ${image:-farrellit/ec2metadata:latest}

if which open > /dev/null 2>&1; then
  open http://169.254.169.254
else
  echo "Visit http://169.254.169.254"
fi
