#!/bin/sh

# dockerd start
dockerd > /var/log/dockerd.log 2>&1 &
dockerd_pid=$!
sleep 2

# pull inner images
kubeadm config images pull
docker pull quay.io/coreos/flannel:v0.11.0-amd64

# dockerd cleanup (remove the .pid file as otherwise it prevents
# dockerd from launching correctly inside sys container)
kill $dockerd_pid
rm -f /var/run/docker.pid
