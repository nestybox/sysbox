#
# Kubernetes node system container **test** image.
#
# NOTE: MEANT FOR INTERNAL USE BY NESTYBOX; DO NOT MAKE PUBLIC.
#
# This image is a superset of k8s-node image, which includes systemd,
# kubeadm and all k8s control plane pod images. Its main purpose is
# to serve as a testing image for K8s' integration-test suites.
#
# NOTE: THIS IMAGE SHOULD BE BUILT INSIDE THE SYSBOX TEST CONTAINER,
# TO AVOID THE PROBLEMS IN SYSBOX ISSUE 676.
#
# $ docker build -t nestybox/k8s-node-test:v1.18.2 .
#

FROM nestybox/k8s-node:v1.18.2

ARG k8s_version=v1.18.2

# Debug/Testing utilities
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
    bridge-utils \
    && rm -rf /var/lib/apt/lists/*
