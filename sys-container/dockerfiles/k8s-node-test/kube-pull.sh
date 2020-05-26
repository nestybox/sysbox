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
containerd > /var/log/containerd.log 2>&1 &
sleep 2

# pull inner images
kubeadm config images pull --kubernetes-version=$k8s_version
