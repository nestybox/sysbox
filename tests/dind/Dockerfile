# Note: we use alpine-docker-dbg:3.11 as it comes with Docker 19.03 and helps
# us avoid sysbox issue #187 (lchown error when Docker v20+ pulls inner images
# with special devices)
FROM ghcr.io/nestybox/alpine-docker-dbg:3.11

COPY docker-pull.sh /usr/bin
RUN chmod +x /usr/bin/docker-pull.sh && docker-pull.sh
RUN rm /usr/bin/docker-pull.sh

# Alternative one-liner (but needs to cleanup docker.pid)
#RUN bash -c 'declare -a cmds=("dockerd" "docker pull busybox" "rm /var/run/docker.pid"); for cmd in "${cmds[@]}"; do $cmd & sleep 2; done'
