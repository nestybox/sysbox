FROM ghcr.io/nestybox/alpine-docker-dbg

COPY ctr-pull.sh /usr/bin
RUN chmod +x /usr/bin/ctr-pull.sh && ctr-pull.sh
RUN rm /usr/bin/ctr-pull.sh
