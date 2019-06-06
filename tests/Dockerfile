#
# Sysvisor Test Container Dockerfile
#
# This Dockerfile creates the sysvisor test container image. The image
# contains all dependencies needed to build, run, and test sysvisor.
#
# The image does not contain sysvisor itself; the sysvisor repo
# must be bind mounted into the image. It can then be built,
# installed, and executed within the container.
#
# The image must be run as a privileged container (i.e., docker run --privileged ...)
# Refer to the sysvisor Makefile test targets.
#
# This Dockerfile is based on a similar Dockerfile in the OCI runc
# github repo, but adapted to sysvisor testing.
#
# Instructions:
#
# docker build -t sysvisor-test .
#

FROM golang:1.12-stretch

RUN apt-get update && apt-get install -y \
    build-essential \
    procps \
    nano \
    less \
    curl \
    sudo \
    gawk \
    iptables \
    jq \
    pkg-config \
    libaio-dev \
    libcap-dev \
    libprotobuf-dev \
    libprotobuf-c0-dev \
    libnl-3-dev \
    libnet-dev \
    libseccomp2 \
    libseccomp-dev \
    protobuf-c-compiler \
    protobuf-compiler \
    python-minimal \
    uidmap \
    kmod \
    unzip \
    --no-install-recommends \
    && apt-get clean

# Activate golang's modules functionality and install its latest (top-of-tree) binary.
# These instructions may be eliminated upon arrival of 1.13 release (ETA: Aug-2019).
ENV GO111MODULE=on
RUN go get golang.org/dl/gotip \
    && gotip download \
    && gotip env -w GONOSUMDB=/root/nestybox

# Add a dummy user for the rootless integration tests; needed by the
# `git clone` operations below.
RUN useradd -u1000 -m -d/home/rootless -s/bin/bash rootless

# install bats
RUN cd /tmp \
    && git clone https://github.com/sstephenson/bats.git \
    && cd bats \
    && git reset --hard 03608115df2071fff4eaaff1605768c275e5f81f \
    && ./install.sh /usr/local \
    && rm -rf /tmp/bats

# install protoc compiler for gRPC
RUN mkdir -p ~/bin/protoc \
    && cd ~/bin/protoc/ \
    && wget https://github.com/protocolbuffers/protobuf/releases/download/v3.6.1/protoc-3.6.1-linux-x86_64.zip \
    && unzip protoc-3.6.1-linux-x86_64.zip \
    && cp -r include/* /usr/local/include/ \
    && cp bin/protoc /usr/local/bin/ \
    && cd \
    && rm -rf ~/bin/protoc/ \
    && go get -u github.com/golang/protobuf/protoc-gen-go

# install Docker (used by most sysvisor tests to launch sys containers)
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

# install pjdfstest suite (used to test shiftfs posix compliance)
RUN apt-get install -y autoconf
RUN cd /root \
    && git clone https://github.com/pjd/pjdfstest.git \
    && cd pjdfstest \
    && autoreconf -ifs \
    && ./configure \
    && make pjdfstest \
    && cp pjdfstest /usr/local/bin


# sysvisor deps
RUN apt-get update && apt-get install -y \
    fuse

# sysvisor env
RUN useradd sysvisor \
    && mkdir -p /var/lib/sysvisorfs

# nestybox docker hub login credentials (insecure)
COPY .docker/config.json /root/.docker/config.json

COPY scr/testContainerInit /usr/bin
COPY scr/testContainerCleanup /usr/bin

RUN mkdir -p /root/nestybox
WORKDIR /root/nestybox/sysvisor
CMD /bin/bash
