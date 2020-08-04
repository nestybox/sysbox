#
# Ubuntu Bionic + Docker + Compose
#
# Instructions for Docker compose installation taken from:
# https://docs.docker.com/compose/install/
#

FROM nestybox/ubuntu-bionic-docker:latest

RUN curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose
