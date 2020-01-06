FROM alpine:latest

RUN apk update && apk add \
    bash \
    curl \
    findmnt \
    nano \
    strace \
    tree \
    libcap

RUN sed -i 's/v3.10/latest-stable/g' /etc/apk/repositories && apk update && apk add docker
