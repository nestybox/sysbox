#
# Ubuntu Bionic + Docker
#
# Instructions for docker installation taken from:
# https://docs.docker.com/install/linux/docker-ce/ubuntu/
#

FROM nestybox/ubuntu-bionic-docker:latest

# Debug utilities
RUN apt-get update && apt-get install -y \
       procps \
       psmisc \
       nano \
       strace \
       net-tools \
       less \
       wget \
       iproute2

CMD ["/bin/bash"]
