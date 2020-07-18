#!/bin/sh

# start dockerd (needed for building KinD)
dockerd > /var/log/dockerd.log 2>&1 &
sleep 3

# build K8s.io KinD
cd /home/admin/kind
git pull
make
cp bin/kind /usr/local/bin

# Remove the golang image used during the kind build (not needed anymore)
docker image rm $(docker image ls -aq)

# Get the nestybox/kindestnode:v1.18.2 image (temporarily needed for
# the kind cluster nodes to bypass a bug in the OCI runc used inside
# these nodes).
docker pull nestybox/kindestnode:v1.18.2
