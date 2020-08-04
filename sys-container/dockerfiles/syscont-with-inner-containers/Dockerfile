#
# Sample Dockerfile to build a system container image that include inner container images.
#
# Build with:
#   $ docker build -t nestybox/syscont-with-inner-containers:latest .
#
# Run with:
#   $ docker run -it --runtime=sysbox-runc --hostname=syscont nestybox/syscont-with-inner-containers:latest

FROM nestybox/alpine-docker

COPY docker-pull.sh /usr/bin
RUN chmod +x /usr/bin/docker-pull.sh && docker-pull.sh && rm /usr/bin/docker-pull.sh
