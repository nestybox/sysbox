This directory contains tests that verify kubernetes-in-docker (kind)
functionality. Each test launches one or more sys containers using
docker, and within each sys container runs kubernetes + docker. That
is, each sys container becomes a K8s node. The inner K8s in each sys
container is then commanded to create pod deployments.
