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

# Do not use the lo interface in Linux.  Any IPs assigned outside of the
# 127.0.0.0/8 network will be shared across all interfaces.  This means your
# 169.254.169.254 IP and role assumption will be shared across the network!
# Why not use a docker net?  Then we can be OS-agnostic.

$sudo $dockercmd network inspect $DOCKERNETNAME &> /dev/null
if [[ $? != 0 ]] ; then
  $sudo $dockercmd network create \
    --gateway $DOCKERGATEWAY \
    --subnet $DOCKERNET \
    -o com.docker.network.bridge.enable_icc=true \
    -o com.docker.network.bridge.enable_ip_masquerade=true \
    -o com.docker.network.bridge.host_binding_ipv4=0.0.0.0 \
    -o com.docker.network.bridge.name=$DOCKERNETNAME \
    -o com.docker.network.driver.mtu=1500 \
    $DOCKERNETNAME
fi

$sudo $dockercmd run \
  --name ec2metadata \
  -e RACK_ENV=${RACK_ENV:-production} \
  --network $DOCKERNETNAME \
  -p 80:80 \
  -v `ls -d ${AWS_PROFILE_PATH:-~/.aws}`:/root/.aws \
  -e MYNAME \
  ${args:---rm -d} \
  ${image:-farrellit/ec2metadata:latest}
