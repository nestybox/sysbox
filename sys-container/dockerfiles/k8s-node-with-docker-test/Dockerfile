#
# Kubernetes node system container **test** image.
#
# NOTE: MEANT FOR INTERNAL USE BY NESTYBOX; DO NOT MAKE PUBLIC.
#
# This image includes systemd, docker, kubeadm, and all k8s control
# plane pod images.
#
# NOTE: THIS IMAGE SHOULD BE BUILT INSIDE THE SYSBOX TEST CONTAINER,
# TO AVOID THE PROBLEMS IN SYSBOX ISSUE 676.
#
# $ docker build -t nestybox/k8s-node-with-docker-test:v1.18.2 .
#

FROM nestybox/ubuntu-bionic-systemd-docker:latest

ARG k8s_version=v1.18.2

# Install kubeadm
#
# Note: see list of supported packages here: https://packages.cloud.google.com/apt/dists/

RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
RUN apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
RUN apt-get update && apt-get install --no-install-recommends -y \
	kubelet="${k8s_version#v}"-00 \
	kubectl="${k8s_version#v}"-00 \
	kubeadm="${k8s_version#v}"-00

# Pull k8s control plane container images into sys container image
COPY kube-pull.sh /usr/bin/
RUN chmod +x /usr/bin/kube-pull.sh && kube-pull.sh $k8s_version && rm /usr/bin/kube-pull.sh

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
