ARG GO_IMAGE
ARG BUILD_IMAGE=ubuntu:disco
FROM ${GO_IMAGE} as golang

FROM ${BUILD_IMAGE}

RUN apt-get update &&  \
    apt-get install -y \
    curl               \
    devscripts         \
    dkms               \
    equivs             \
    git                \
    wget               \
    pkg-config         \
    libnet-dev         \
    libseccomp2        \
    libseccomp-dev

ARG GO_VERSION
ENV GOPATH /go
ENV PATH $PATH:/usr/local/go/bin:$GOPATH/bin

ARG COMMON_FILES
COPY ${COMMON_FILES} /root/build-deb/debian
RUN mk-build-deps -t "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y" -i /root/build-deb/debian/control

COPY sources/ /sources

ENV DISTRO ubuntu
ENV SUITE disco

COPY --from=golang /usr/local/go /usr/local/go

# Activate golang's modules functionality and install its latest (top-of-tree) binary.
# These instructions may be eliminated upon arrival of 1.13 release (ETA: Aug-2019).
ENV GO111MODULE=on
RUN go get golang.org/dl/gotip \
    && gotip download \
    && gotip env -w GONOSUMDB=github.com/nestybox

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

WORKDIR /root/build-deb
COPY build-deb /root/build-deb/build-deb

# Fetch all kernel-headers supported by Nestybox's shiftfs module. This will be
# used to build shiftfs' module for all the kernel releases that we may encounter.
#
# TODO: Find a more efficient/programmatic approach to generate this list.
RUN apt-get install -y \
    linux-headers-5.0.0-13-generic \
    linux-headers-5.0.0-15-generic \
    linux-headers-5.0.0-16-generic \
    linux-headers-5.0.0-17-generic \
    linux-headers-5.0.0-19-generic \
    linux-headers-5.0.0-20-generic \
    linux-headers-5.0.0-21-generic \
    linux-headers-5.0.0-23-generic

ENTRYPOINT ["/root/build-deb/build-deb"]