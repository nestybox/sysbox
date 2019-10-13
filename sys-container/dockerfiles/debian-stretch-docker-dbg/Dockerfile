#
# Debian Stretch + Docker
#
# Instructions for docker installation taken from:
# https://docs.docker.com/install/linux/docker-ce/debian/
#

FROM nestybox/debian-disco-docker:latest

# Debug utilities
RUN apt-get update && apt-get install -y \
       procps \
       psmisc \
       nano \
       strace \
       net-tools \
       wget

#
# The following steps could be used as an alternative to the
# docker-ce install above. They only install the docker engine.
# I got these from here:
# https://gist.github.com/apokalyptik/99cefb3d2e16b9b0c3141e222f3267db#file-set-up-the-master-md
#
# apt-key adv \
#   --keyserver hkp://p80.pool.sks-keyservers.net:80 \
#   --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
# echo 'deb https://apt.dockerproject.org/repo debian-jessie main' \
#   > /etc/apt/sources.list.d/docker.list
# apt-get update
# apt-get -fqqy install docker-engine
