# Nestybox's Drone-server Dockerfile.
#
# Description:
#
# Dockerfile to construct a system container to host Drone-server functionality.
# The obtained image will incorporate the drone-server binary, as well as the
# Docker package required to instantiate 'slave' containers to execute continous
# integration tasks. Both daemons (drone-server and dockerd) will be managed
# through supervisord process manager.
#
# Requirements:
#
# A supervisord.conf file in charge of launching dockerd & drone-server daemons,
# must be provided as part of this image compilation process. See example below:
#
# ---
# $ cat supervisord.conf
# [supervisord]
# stdout_logfile=/dev/stdout
# stdout_logfile_maxbytes=0
# nodaemon=true
#
# [program:dockerd]
# command=/usr/bin/dockerd
# priority=1
# autostart=true
# autorestart=true
# startsecs=0
#
# [program:drone-server]
# command=/bin/drone-server
# priority=2
# autostart=true
# autorestart=true
# startsecs=0
# ---
#
# Container initialization:
#
# $ docker run --runtime=sysbox-runc \
#  --env=DRONE_GITHUB_SERVER=https://github.com \
#  --env=DRONE_GITHUB_CLIENT_ID=${DRONE_GITHUB_CLIENT_ID} \
#  --env=DRONE_GITHUB_CLIENT_SECRET=${DRONE_GITHUB_CLIENT_ID} \
#  --env=DRONE_SERVER_HOST=${DRONE_SERVER_HOST} \
#  --env=DRONE_SERVER=http://${DRONE_SERVER_HOST} \
#  --env=DRONE_USER_CREATE=username:nestybox,admin:true,token:${DRONE_TOKEN} \
#  --publish=80:80 --publish=443:443 \
#  -d --rm --name=drone nestybox/ubuntu-bionic-drone-server
#
#  [ refer to Drone's official documentation for more details ]
#


#######################
#  Drone compilation  #
#######################

FROM golang:latest as golang
RUN cd /root && \
    git clone https://github.com/drone/drone.git && \
    cd drone && \
    sh scripts/build.sh

RUN cd /root && \
    git clone https://github.com/drone/drone-cli.git && \
    cd drone-cli && \
    sh .drone.sh


########################
#  Drone installation  #
########################

FROM ubuntu:bionic
EXPOSE 80 443
VOLUME /data

ENV GODEBUG netdns=go
ENV XDG_CACHE_HOME /data
ENV DRONE_DATABASE_DRIVER sqlite3
ENV DRONE_DATABASE_DATASOURCE /data/database.sqlite
ENV DRONE_RUNNER_OS=linux
ENV DRONE_RUNNER_ARCH=amd64
ENV DRONE_SERVER_PORT=:80
ENV DRONE_SERVER_HOST=localhost
ENV DRONE_DATADOG_ENABLED=true
ENV DRONE_DATADOG_ENDPOINT=https://stats.drone.ci/api/v1/series

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Add previously built drone binaries.
COPY --from=golang /root/drone/release/linux/drone-server /bin/
COPY --from=golang /root/drone-cli/release/linux/amd64/drone /bin/


#########################
#  Docker installation  #
#########################

RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-transport-https \
            ca-certificates curl gnupg-agent software-properties-common && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    apt-key fingerprint 0EBFCD88

RUN add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"

RUN apt-get update && \
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io && \
    rm -rf /var/lib/apt/lists/*


##############################
#  Supervisord installation  #
##############################

RUN apt-get update && apt-get install -y --no-install-recommends supervisor && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
CMD ["/usr/bin/supervisord"]
