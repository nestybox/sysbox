#
# Sample system container with alpine + supervisord + sshd + docker
#
# Run with:
#
# $ docker run --runtime=sysbox-runc -d -P <this-image>
#

FROM alpine:latest

# docker
RUN sed -i 's/v3.10/latest-stable/g' /etc/apk/repositories && \
    apk add --update docker && \
    rm  -rf /tmp/* /var/cache/apk/*

# supervisord
RUN apk add --update supervisor && rm  -rf /tmp/* /var/cache/apk/*
RUN mkdir -p /var/log/supervisor
#COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY supervisord.conf /etc/

# sshd
RUN apk add --update openssh && rm  -rf /tmp/* /var/cache/apk/*
RUN mkdir /var/run/sshd
RUN echo 'root:root' | chpasswd
RUN sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config
RUN mkdir /root/.ssh
RUN ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa
EXPOSE 22

# entrypoint
COPY docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
RUN chmod +x /usr/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
