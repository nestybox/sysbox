FROM ghcr.io/nestybox/ubuntu-jammy-docker

COPY ctr-pull.sh /usr/bin
RUN chmod +x /usr/bin/ctr-pull.sh && ctr-pull.sh
RUN rm /usr/bin/ctr-pull.sh
