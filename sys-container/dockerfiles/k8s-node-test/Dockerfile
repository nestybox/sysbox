#
# Kubernetes node system container **test** image.
#
# NOTE: MEANT FOR INTERNAL USE BY NESTYBOX; DO NOT MAKE PUBLIC.
#
# This image includes systemd, kubeadm, and all k8s control plane pod images.
#
# NOTE: THIS IMAGE SHOULD BE BUILT INSIDE THE SYSBOX TEST CONTAINER,
# TO AVOID THE PROBLEMS IN SYSBOX ISSUE 676.
#
# $ docker build -t nestybox/k8s-node-test:v1.18.2 .
#

FROM nestybox/ubuntu-bionic-systemd:latest

ARG k8s_version=v1.18.2

# containerd
RUN apt-get update && apt-get install --no-install-recommends -y \
       apt-transport-https \
       ca-certificates \
       curl \
       gnupg-agent \
       software-properties-common

RUN apt-get update && apt-get install --no-install-recommends -y containerd

# kubeadm
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

# bash completion
RUN apt-get update && apt-get install bash-completion && echo ". /etc/bash_completion" >> /etc/bash.bashrc
RUN echo "source <(kubectl completion bash)" >> /root/.bashrc

# Override the OCI runc with one that has a fix for redundant device
# mounts. This is needed as otherwise the kube-proxy pod fails to start because
# the kube-proxy container spec created by containerd specifies mounts under
# /dev explicitly, even though runc does them implicitly already. Runc fails to
# detect the redundant /dev mounts and fails upon doing the redundant mount of
# /dev/tty with "no such device or address" error. We use an OCI runc that has
# been patched to detect such redundant mounts.
COPY runc /usr/local/sbin/runc
RUN chmod +x /usr/local/sbin/runc

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
