#
# K8s system container image based on ubuntu-bionic
#
# This image includes systemd, docker, kubeadm, and all k8s control
# plane container images.
#

FROM nestybox/ubuntu-bionic-systemd-docker:latest

# Install kubeadm
#
# Note: see list of supported packages here: https://packages.cloud.google.com/apt/dists/

RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
RUN apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
RUN apt-get update && apt-get install --no-install-recommends -y kubeadm

# Pull k8s control plane container images into sys container image
COPY kube-pull.sh /usr/bin/
RUN chmod +x /usr/bin/kube-pull.sh && kube-pull.sh && rm /usr/bin/kube-pull.sh

# Docker daemon config
COPY daemon.json /etc/docker/

# Debug utilities
RUN apt-get update && apt-get install --no-install-recommends -y \
    lsof \
    less \
    nano \
    psmisc \
    iproute2 \
    iputils-ping \
    jq \
    net-tools \
    dnsutils \
    tcpdump \
    bridge-utils

# bash completion
RUN apt-get update && apt-get install bash-completion && echo ". /etc/bash_completion" >> /etc/bash.bashrc
RUN echo "source <(kubectl completion bash)" >> /root/.bashrc
