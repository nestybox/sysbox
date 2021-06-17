#!/bin/bash -e
#
# Script to run Sysbox integration testcases to validate Kubernetes-in-Docker (Kind)
# support.
#

progName=$(basename "$0")

# Argument testName is optional
if [ $# -eq 1 ]; then
  printf "\nExecuting $1 ... \n"
  bats --tap $1
  return
fi

# the kind tests need plenty storage (otherwise kubelet fails);
# remove all docker images from prior tests to make room, and
# remove all docker images after test too.
printf "\n"
docker system prune -a -f

printf "\nExecuting kind testcases with flannel cni ... \n"
bats --tap tests/kind/kind-flannel.bats

printf "\nExecuting kind testcases with custom docker networks ... \n"
bats --tap tests/kind/kind-custom-net.bats

printf "\n"
docker system prune -a -f
