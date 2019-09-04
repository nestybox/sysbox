ARG GO_IMAGE
ARG BUILD_IMAGE=ubuntu:cosmic
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
ENV SUITE cosmic

COPY --from=golang /usr/local/go /usr/local/go

# Explicit activation of go-module feature (by default in 'auto' mode as per Go 1.13).
ENV GO111MODULE=on
RUN go env -w GONOSUMDB=github.com/nestybox

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
COPY changelog_convert.sh /root/build-deb/changelog_convert.sh

ENTRYPOINT ["/root/build-deb/build-deb"]