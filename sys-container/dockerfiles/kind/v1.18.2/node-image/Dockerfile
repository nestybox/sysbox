# Dockerfile for k8s.io KinD node, when using KinD + Sysbox
#
# The image is almost entirely based on KinD's official image
# but has a custom entrypoint and a custom runc to overcome
# problems that arise when using the official entrypoint
# and default runc (see below).
#
# Build with:
#
# $ docker build -t nestybox/kindestnode:v1.18.2 .
#
# Deploy with the KinD CLI:
#
# $ kind create cluster --image nestybox/kindestnode:v1.18.2
#

FROM kindest/node:v1.18.2

# Override the OCI runc with one that has a fix for redundant device
# mounts. This is needed as otherwise the kube-proxy pod fails to
# start because the kube-proxy container spec specifies mounts under
# /dev explicitly, even though runc does them implicitly already. Runc
# fails to detect the redundant /dev mounts and fails upon doing the
# redundant mount of /dev/tty with "no such device or address"
# error. We use an OCI runc that has been patched to detect such
# redundant mounts.
COPY runc /usr/local/sbin/runc
RUN chmod +x /usr/local/sbin/runc
