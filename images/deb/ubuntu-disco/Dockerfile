ARG GO_IMAGE
ARG BUILD_IMAGE=ubuntu:disco
FROM ${GO_IMAGE} as golang

FROM ${BUILD_IMAGE}

RUN apt-get update &&  \
    apt-get install -y \
    curl               \
    devscripts         \
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

ENTRYPOINT ["/root/build-deb/build-deb"]