This directory contains tests that verify docker-in-docker (dind)
functionality. Each test launches one or more sys container using
docker, and within each sys container runs another docker instance
(the inner docker). The inner docker in each sys container is then
commanded to launch inner containers.
