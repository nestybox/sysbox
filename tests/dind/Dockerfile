FROM nestybox/alpine-docker-dbg

COPY docker-pull.sh /usr/bin
RUN chmod +x /usr/bin/docker-pull.sh && docker-pull.sh
RUN rm /usr/bin/docker-pull.sh

# Alternative one-liner (but needs to cleanup docker.pid)
#RUN bash -c 'declare -a cmds=("dockerd" "docker pull busybox" "rm /var/run/docker.pid"); for cmd in "${cmds[@]}"; do $cmd & sleep 2; done'
