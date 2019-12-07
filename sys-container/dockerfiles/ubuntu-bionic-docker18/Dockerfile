#
# Ubuntu Bionic + Docker 18.09.8
#
# NOTE: this dockerfile relies on deb packages for Docker 18.09 that
# must be downloaded and copied into this directory before launching
# the docker build.
#
# They can be obtained from https://download.docker.com/linux/ubuntu/dists/bionic/pool/stable/amd64/
#

FROM ubuntu:bionic

# Docker 18.09.8 install
RUN apt-get update && apt-get install --no-install-recommends -y \
       apt-transport-https \
       ca-certificates \
       curl \
       gnupg-agent \
       software-properties-common \
       iptables

RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN apt-key fingerprint 0EBFCD88
RUN add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"

RUN apt-get update && apt-get install --no-install-recommends -y \
    containerd.io

# Install the docker 18 deb packages
COPY docker-ce-cli_18.09.8_3-0_ubuntu-bionic_amd64.deb /root/
COPY docker-ce_18.09.8_3-0_ubuntu-bionic_amd64.deb /root/

RUN dpkg -i /root/docker-ce-cli_18.09.8_3-0_ubuntu-bionic_amd64.deb
RUN dpkg -i /root/docker-ce_18.09.8_3-0_ubuntu-bionic_amd64.deb
