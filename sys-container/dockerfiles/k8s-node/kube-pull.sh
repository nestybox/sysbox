#!/bin/sh

#
# Runs inside the K8s node system container; requests kubeadm to pull K8s
# control-plane components.
#

usage() {
  echo "\nUsage: $0 <k8s-version>\n"
  echo "E.g., $0 v1.18.2"
}

if [ "$#" -ne 1 ]; then
    echo "Invalid number of arguments. Expect 1, got $#".
    usage
    exit 1
fi

k8s_version=$1

# start dockerd
dockerd > /var/log/dockerd.log 2>&1 &
dockerd_pid=$!
sleep 2

# pull inner images
kubeadm config images pull --kubernetes-version=$k8s_version
docker image pull quay.io/coreos/flannel:v0.12.0-amd64

# stop dockerd (remove the .pid file as otherwise it may prevent
# dockerd from launching correctly inside the sys container)
kill $dockerd_pid
rm -f /var/run/docker.pid
