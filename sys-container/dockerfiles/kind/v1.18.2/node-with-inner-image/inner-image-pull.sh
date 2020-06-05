#!/bin/sh

# containerd start
containerd > /var/log/containerd.log 2>&1 &
sleep 2

# use containerd to pull inner images into the k8s.io namespace (used by KinD).
ctr --namespace=k8s.io image pull docker.io/library/nginx:latest
