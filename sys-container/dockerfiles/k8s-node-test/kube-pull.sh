#!/bin/sh

#
# Pulls K8s control-plane components via kubeadm into the K8s node system
# container image.
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

# dockerd start
dockerd > /var/log/dockerd.log 2>&1 &
dockerd_pid=$!
sleep 2

# pull inner images
kubeadm config images pull --kubernetes-version=$k8s_version
docker pull quay.io/coreos/flannel:v0.11.0-amd64

# dockerd cleanup (remove the .pid file as otherwise it prevents
# dockerd from launching correctly inside sys container)
kill $dockerd_pid
rm -f /var/run/docker.pid
