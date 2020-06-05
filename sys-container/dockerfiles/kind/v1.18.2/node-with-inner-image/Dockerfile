FROM nestybox/kindestnode:v1.18.2

# Pull inner images using containerd
COPY inner-image-pull.sh /usr/bin/
RUN chmod +x /usr/bin/inner-image-pull.sh && inner-image-pull.sh && rm /usr/bin/inner-image-pull.sh
