#
# kindind: kubernetes-in-docker ... in docker :)
#
# Usage:
#
# $ docker run --runtime=sysbox-runc -it --rm -P --name=syscont nestybox/kindind
#
# This will spawn a sys container which contains systemd, docker, and the K8s.io
# KinD tool inside. Systemd login is "admin/admin". Once you log in you can run
# K8s.io KinD as if you were in a VM. E.g.,:
#
# $ kind create cluster --image=nestybox/kindestnode:v1.18.2
#
# The "nestybox/kindestnode:v1.18.2" image is currently required due to a bug in
# the OCI runc that prevents it from running correctly inside a system
# container. Note that in this case said runc is running inside a privileged
# container (deployed by k8s.io kind) that is inside a system container (where
# that privileged container is only privileged with respect to the system
# container, not with respect to the host).
#

FROM nestybox/ubuntu-bionic-systemd-docker:latest

RUN apt-get update && apt-get install -y \
    git \
    make

# kubectl (with bash completion)
ARG k8s_version=v1.18.2
RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -  \
    && echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install kubectl="${k8s_version#v}"-00 \
    && apt-get install bash-completion \
    && kubectl completion bash >/etc/bash_completion.d/kubectl \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# K8s.io KinD
RUN git clone https://github.com/kubernetes-sigs/kind.git /home/admin/kind

# Build the KinD tool
COPY build-kind.sh /usr/bin
RUN chmod +x /usr/bin/build-kind.sh && build-kind.sh && rm /usr/bin/build-kind.sh
