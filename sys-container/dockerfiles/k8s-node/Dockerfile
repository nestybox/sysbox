# Sample Kubernetes (K8s) node system container image.
#
# Containers deployed with this image acts as K8s nodes.
#
# The image creates a container that includes systemd, kubeadm, docker, and all
# k8s control plane pod images (apiserver, kubeproxy, etc.).
#
# You must deploy the container with the Sysbox container runtime (see below).
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
# $ docker build -t nestybox/k8s-node:v1.18.2 .
#
# Once the build completes, you can revert the default runtime config if you wish.
#
# Deploy k8s-node containers with:
#
# $ docker run --runtime=sysbox-runc --rm -d --name k8s-master nestybox/k8s-node:v1.18.2
# $ docker run --runtime=sysbox-runc --rm -d --name k8s-worker-0 nestybox/k8s-node:v1.18.2
# $ docker run --runtime=sysbox-runc --rm -d --name k8s-worker-1 nestybox/k8s-node:v1.18.2
# ...
#
# Then run 'kubeadm init' in them just as you would on a physical host or VM.

FROM nestybox/ubuntu-bionic-systemd:latest

ARG k8s_version=v1.18.2

# Install Docker.
RUN apt-get update && apt-get install --no-install-recommends -y                        \
       apt-transport-https                                                              \
       ca-certificates                                                                  \
       curl                                                                             \
       gnupg-agent                                                                      \
       software-properties-common                                                       \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -          \
    && apt-key fingerprint 0EBFCD88                                                     \
    && add-apt-repository                                                               \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu                       \
       $(lsb_release -cs)                                                               \
       stable"                                                                          \
    && apt-get update                                                                   \
    && apt-get install --no-install-recommends -y docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*                                                      \
    # Add user "admin" to the Docker group                                              \
    && usermod -a -G docker admin


# Install Kubeadm.
#
# Note: we use kubeadm for Ubuntu Xenial because a version for Bionic is not available;
# see https://packages.cloud.google.com/apt/dists/
RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add    \
    && apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"        \
    && apt-get update && apt-get install --no-install-recommends -y kubeadm             \
    && rm -rf /var/lib/apt/lists/*

# Preload k8s control plane container images into the sys container image.
COPY kube-pull.sh /usr/bin/
RUN chmod +x /usr/bin/kube-pull.sh && kube-pull.sh $k8s_version && rm /usr/bin/kube-pull.sh

# Docker daemon config.
COPY daemon.json /etc/docker/

# bash completion
RUN apt-get update                                                             \
    && mkdir -p /etc/bash_completion.d                                         \
    && apt-get install bash-completion                                         \
    && rm -rf /var/lib/apt/lists/*                                             \
    && echo "source /etc/profile.d/bash_completion.sh" >> /root/.bashrc        \
    && echo "source <(kubectl completion bash)" >> /root/.bashrc               \
    && echo "source /etc/profile.d/bash_completion.sh" >> /home/admin/.bashrc  \
    && echo "source <(kubectl completion bash)" >> /home/admin/.bashrc
