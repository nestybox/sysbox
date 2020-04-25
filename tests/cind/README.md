This directory contains tests that verify containerd-in-docker (cind)
functionality. Each test launches one or more sys containers using
docker, and within each sys container runs a containerd instance. The
inner containerd in each sys container is then commanded to pull
images and launch inner containers.
