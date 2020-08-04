# nestybox/kindestnode
#
# This image is almost entirely based on the K8s.io KinD node image
# (kindest/node) but has a custom runc to overcome problems that arise when
# using the default runc (see below).
#
# Build with:
#
# $ docker build -t nestybox/kindestnode:v1.18.2 .
#
# Deploy with the K8s.io KinD tool:
#
# $ kind-sysbox create cluster --image nestybox/kindestnode:v1.18.2
#

FROM kindest/node:v1.18.2

# The OCI runc program has a bug that prevents it from working
# correctly inside unprivileged containers under certain scenarios.
# We use an OCI runc that contains the fix.
COPY runc /usr/local/sbin/runc
RUN chmod +x /usr/local/sbin/runc
