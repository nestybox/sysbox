This directory contains tests that verify kubernetes-in-docker (kind)
functionality. Each test launches one or more sys containers using
docker, and within each sys container runs kubernetes + docker. That
is, each sys container is a K8s node. The inner K8s in each sys
container is then commanded to create pod deployments, services, etc.

NOTES:

* If the time it takes to bring up the K8s cluster is excessive (> 4
  minutes for 3 node cluster), make sure that the disk utilization in
  your machine is < 75%. We've noticed that when disk utilization is
  above this threshold, the kubelet refuses to initialize properly.
