#
# ubuntu base image + (official) docker
#
# Instructions for docker installation taken from:
# https://docs.docker.com/install/linux/docker-ce/ubuntu/
#

FROM ubuntu:disco
RUN apt-get update

# Useful utilities
RUN apt-get install -y \
       procps \
       nano \
       strace \
       net-tools \
       less \
       wget

# Docker install
RUN apt-get install -y \
       apt-transport-https \
       ca-certificates \
       curl \
       gnupg-agent \
       software-properties-common
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN apt-key fingerprint 0EBFCD88

# need edge and test repos as there is stable version of docker for ubuntu:disco yet
RUN add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable edge test"
RUN apt-get update
RUN apt-get install -y docker-ce docker-ce-cli containerd.io
