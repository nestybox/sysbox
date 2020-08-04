#
# Alpine + Docker
#

FROM alpine:latest

RUN sed -i 's/v3.10/latest-stable/g' /etc/apk/repositories && apk update && apk add docker
