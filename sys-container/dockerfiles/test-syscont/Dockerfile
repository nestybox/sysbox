#
# Alpine + docker + a bunch of inner container images
#
# Instructions for docker installation taken from:
# https://docs.docker.com/install/linux/docker-ce/ubuntu/
#
# TODO
# Use light-weight base (alpine)
# Embed other images inside


FROM alpine:3.10

RUN apk update && apk add \
    bash \
    curl \
    docker \
    findmnt \
    nano \
    strace

# Inner container images (embedded in sys container image)
COPY elasticsearch_5.6.16-alpine.tar /root/img/elasticsearch_5.6.16-alpine.tar
COPY alpine_3.10.tar /root/img/alpine_3.10.tar
COPY httpd_alpine.tar /root/img/httpd_alpine.tar
COPY fluentd_edge.tar /root/img/fluentd_edge.tar
COPY python_alpine.tar /root/img/python_alpine.tar
COPY mysql_server_5.6.tar /root/img/mysql_server_5.6.tar
COPY nginx_mainline_alpine.tar /root/img/nginx_mainline_alpine.tar
COPY postgres_alpine.tar /root/img/postgres_alpine.tar
COPY prometheus.tar /root/img/prometheus.tar
COPY redis_5.0.5_alpine.tar /root/img/redis_5.0.5_alpine.tar
COPY telegraf-1.12-alpine.tar /root/img/telegraf-1.12-alpine.tar
COPY influxdb_1.7-alpine.tar /root/img/influxdb_1.7-alpine.tar

# TODO:

# Add remaining images for tests; here and in get-img script. modify appropriate test.
