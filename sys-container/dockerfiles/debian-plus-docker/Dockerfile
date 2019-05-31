#
# debian-stretch base image + (official) docker
#
# Instructions for docker installation taken from:
# https://docs.docker.com/install/linux/docker-ce/debian/
#

FROM debian:stretch
RUN apt-get update

# Useful utilities
RUN apt-get install -y \
       procps \
       nano \
       strace

# Docker install
RUN apt-get install -y \
       apt-transport-https \
       ca-certificates \
       curl \
       gnupg2 \
       software-properties-common
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN apt-key fingerprint 0EBFCD88
RUN add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/debian \
       $(lsb_release -cs) \
       stable"
RUN apt-get update
RUN apt-get install -y docker-ce docker-ce-cli containerd.io

#
# The following steps could be used as an alternative to the
# docker-ce install above. They only install the docker engine.
# I got these from here:
# https://gist.github.com/apokalyptik/99cefb3d2e16b9b0c3141e222f3267db#file-set-up-the-master-md
#
# apt-key adv \
#   --keyserver hkp://p80.pool.sks-keyservers.net:80 \
#   --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
# echo 'deb https://apt.dockerproject.org/repo debian-jessie main' \
#   > /etc/apt/sources.list.d/docker.list
# apt-get update
# apt-get -fqqy install docker-engine
