# Dockerfile for 'KinD + Sysbox' integration-testing purposes.
#
# Build with:
#
# $ docker build -t nestybox/kindestnode-dbg:v1.18.2 .
#

FROM nestybox/kindestnode:v1.18.2

RUN apt-get update && apt-get install --no-install-recommends -y dnsutils

# Pull inner images using containerd
COPY inner-image-pull.sh /usr/bin/
RUN chmod +x /usr/bin/inner-image-pull.sh \
    && inner-image-pull.sh \
    && rm /usr/bin/inner-image-pull.sh
