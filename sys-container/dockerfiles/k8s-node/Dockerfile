#
# Kubernetes node system container image.
#
# This image includes systemd, docker, kubeadm, and all k8s control
# plane pod images.
#
# NOTE: BUILDING THIS IMAGE REQUIRES CONFIGURING SYSBOX-RUNC AS DOCKER'S DEFAULT
#       RUNTIME DURING THE BUILD.
#
# $ sudo more /etc/docker/daemon.json
#{
#    "default-runtime": "sysbox-runc",
#    "runtimes": {
#        "sysbox-runc": {
#            "path": "/usr/local/sbin/sysbox-runc"
#        }
#    }
#}
#
# $ sudo systemctl restart docker
# $ docker build -t nestybox/k8s-node:<k8s_version> .
#
# E.g.,
#
# $ docker build -t nestybox/k8s-node:v1.18.2
#
# Deploy k8s-node containers with:
#
# $ docker run --runtime=sysbox-runc --rm -d --name k8s-master nestybox/k8s-node:v1.18.2
# $ docker run --runtime=sysbox-runc --rm -d --name k8s-worker-0 nestybox/k8s-node:v1.18.2
# $ docker run --runtime=sysbox-runc --rm -d --name k8s-worker-1 nestybox/k8s-node:v1.18.2
# ...
#

FROM nestybox/ubuntu-bionic-systemd-docker:latest

ARG k8s_version=v1.18.2

# Install kubeadm
#
# Note: see list of supported packages here: https://packages.cloud.google.com/apt/dists/

RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
RUN apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
RUN apt-get update && apt-get install --no-install-recommends -y kubeadm

# Pull k8s control plane container images into sys container image
COPY kube-pull.sh /usr/bin/
RUN chmod +x /usr/bin/kube-pull.sh && kube-pull.sh $k8s_version && rm /usr/bin/kube-pull.sh

# Docker daemon config
COPY daemon.json /etc/docker/

# bash completion
RUN apt-get update && apt-get install bash-completion && echo ". /etc/bash_completion" >> /etc/bash.bashrc
RUN echo "source <(kubectl completion bash)" >> /root/.bashrc
