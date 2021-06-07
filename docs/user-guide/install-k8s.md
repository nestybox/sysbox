# Sysbox User Guide: Installation in Kubernetes Clusters

This document describes how to install Sysbox on a Kubernetes cluster (i.e., to
deploy pods with Sysbox).

If you are installing Sysbox on a regular host (i.e., not a Kubernetes host),
follow [these instructions](install-package.md) instead.

## Contents

-   [Kubernetes Version Requirements](#kubernetes-version-requirements)
-   [Kubernetes Worker Node Requirements](#kubernetes-worker-node-requirements)
-   [Installation](#installation)
-   [Deploying Pods with Sysbox](#deploying-pods-with-sysbox)
-   [Kubernetes Manifests](#kubernetes-manifests)
-   [Sysbox Container Images](#sysbox-container-images)
-   [Host Volume Mounts](#host-volume-mounts)
-   [Uninstallation](#uninstallation)

## Kubernetes Version Requirements

Sysbox is only supported on Kubernetes v1.20.\* at this time.

The reason for this is that Sysbox currently requires the presence of the CRI-O
runtime v1.20, as the latter introduces support for "rootless pods" (i.e., pods
that use the Linux user-namespace). Since the version of CRI-O and K8s must match, the
K8s version must also be v1.20.\*.

## Kubernetes Worker Node Requirements

Prior to installing Sysbox, ensure each K8s worker node where you will install
Sysbox meets the following requirement:

-   The node's OS must be Ubuntu Focal or Bionic (with a 5.0+ kernel).

## Installation

**NOTE: These instructions work generally in all K8s clusters. For additional
instructions specific to cloud-based K8s clusters, see [here](install-k8s-cloud.md).**

Installation is done via a couple of daemonsets which "drop" the CRI-O and
Sysbox binaries onto the desired K8s nodes and perform all associated config.

-   Install CRI-O on the desired K8s worker nodes:

```console
kubectl label nodes <node-name> crio-install=yes
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/crio-deploy-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/crio-deploy-k8s.yaml
```

-   Install Sysbox on the same nodes:

```console
kubectl label nodes <node-name> sysbox-install=yes
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/sysbox-deploy-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/runtime-class/sysbox-runtimeclass.yaml
```

Then deploy pods with Sysbox [see next section](#deploying-pods-with-sysbox).

NOTES:

-   The installation will temporarily disrupt all pods on the K8s worker nodes
    where CRI-O and Sysbox were installed, for up to 1 minute, as they require
    the kubelet to restart.

-   Sysbox can be installed in all or some of the Kubernetes cluster worker nodes,
    according to your needs.

-   Installing Sysbox on a node does not imply all pods on the node are deployed
    with Sysbox. You can choose which pods use Sysbox via the pod's spec (see next
    section). Pods that don't use Sysbox continue to use the default low-level
    runtime (i.e., the OCI runc) or any other runtime you choose.

-   Pods deployed with Sysbox are managed via K8s just like any other pods; they
    can live side-by-side with non Sysbox pods and can communicate with them
    according to your K8s networking policy.

-   If you hit problems, refer to the [troubleshooting sysbox-deploy-k8s](troubleshoot-k8s.md) doc.

## Deploying Pods with Sysbox

Deploying pods with Sysbox is easy: you only need a couple of things in the pod
spec.

For example, here is a sample pod spec using the `ubuntu-bionic-systemd-docker`
image. It creates a rootless pod that runs systemd as init (pid 1) and comes
with Docker (daemon + CLI) inside:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ubu-bio-systemd-docker
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
spec:
  runtimeClassName: sysbox-runc
  containers:
  - name: ubu-bio-systemd-docker
    image: registry.nestybox.com/nestybox/ubuntu-bionic-systemd-docker
    command: ["/sbin/init"]
  restartPolicy: Never
```

There are two key pieces of the pod's spec that tie it to Sysbox:

-   **"runtimeClassName":** Tells K8s to deploy the pod with Sysbox (rather than the
    default OCI runc). The pods will be scheduled only on the nodes that support
    Sysbox.

-   **"io.kubernetes.cri-o.userns-mode":** Tells CRI-O to launch this as a rootless
    pod (i.e., root user in the pod maps to an unprivileged user on the host)
    and to allocate a range of 65536 Linux user-namespace user and group
    IDs. This is required for Sysbox pods.

Also, for Sysbox pods you typically want to avoid sharing the process (pid)
namespace between containers in a pod. Thus, avoid setting
`shareProcessNamespace: true` in the pod's spec, especially if the pod carries
systemd inside (as otherwise systemd won't be pid 1 in the pod and will fail).

Depending on the size of the pod's image, it may take several seconds for the
pod to deploy on the node. Once the image is downloaded on a node however,
deployment should be very quick (few seconds).

## Kubernetes Manifests

The K8s manifests used for setting up Sysbox can be found [here](../../sysbox-k8s-manifests).

## Sysbox Container Images

The pod in the prior example uses the
`ubuntu-bionic-systemd-docker`, but you can use any container
image you want. Sysbox places no requirements on the container image.

Nestybox has several images which you can find in the [Nestybox Dockerhub registry](https://hub.docker.com/u/nestybox).
Those same images are in the [Nestybox GitHub registry](https://github.com/orgs/nestybox/packages).

We usually rely on `registry.nestybox.com` as an image front-end so that Docker
image pulls are forwarded to the most suitable repository without impacting our
users.

Some of those images carry systemd only, others carry systemd + Docker, other
carry systemd + K8s (yes, you can run K8s inside rootless pods deployed by
Sysbox).

## Host Volume Mounts

To mount host volumes into a K8s pod deployed with Sysbox, the K8s worker node's
kernel **must include** the `shiftfs` kernel module.

**NOTE: shiftfs is currently only supported on Ubuntu kernels and it's installed
automatically by the [sysbox-deploy-k8 daemonset](#installation).**

The need for shiftfs arises because such Sysbox pods are rootless, meaning that
the root user inside the pod maps to a non-root user on the host (e.g., pod user
ID 0 maps to host user ID 296608). Without shiftfs, host directories or files
which are typically owned by users IDs in the range 0->65535 will show up as
`nobody:nogroup` inside the pod.

The shiftfs module solves this problem, as it allows Sysbox to "shift" user
and group IDs inside the pod, such that files owned by users 0->65536 on the
host also show up as owned by users 0->65536 inside the pod.

Once shiftfs is installed, Sysbox will detect this and use it when necessary.
As a user you don't need to know anything about shiftfs; you just setup the pod
with volumes as usual.

For example, the following spec creates a Sysbox pod with ubuntu-bionic + systemd +
docker and mounts host directory `/root/somedir` into the pod's `/mnt/host-dir`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ubu-bio-systemd-docker
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
spec:
  runtimeClassName: sysbox-runc
  containers:
  - name: ubu-bio-systemd-docker
    image: registry.nestybox.com/nestybox/ubuntu-bionic-systemd-docker
    command: ["/sbin/init"]
    volumeMounts:
      - mountPath: /mnt/host-dir
        name: host-vol
  restartPolicy: Never
  volumes:
  - name: host-vol
    hostPath:
      path: /root/somedir
      type: Directory
```

When this pod is deployed, Sysbox will automatically enable shiftfs on the pod's
`/mnt/host-dir`. As a result that directory will show up with proper user-ID and
group-ID ownership inside the pod.

With shiftfs you can even share the same host directory across pods, even if
the pods each get exclusive Linux user-namespace user-ID and group-ID mappings.
Each pod will see the files with proper ownership inside the pod (e.g., owned
by users 0->65536) inside the pod.

## Uninstallation

To uninstall Sysbox:

```console
kubectl delete runtimeclass sysbox-runc
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/sysbox-deploy-rbac.yaml
```

To uninstall CRI-O:

```console
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/crio-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/crio-cleanup-k8s.yaml
sleep 10
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/crio-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/crio-deploy-rbac.yaml
```

NOTES:

-   The uninstallation will temporarily disrupt all pods on the nodes where CRI-O
    and Sysbox were installed, for up to 1 minute, as they require the kubelet to
    restart.

-   The sleep instruction above is to ensure that kubelet has a chance to launch
    the 'cleanup' daemonset before it is removed in the next step.

## Troubleshooting

If you hit problems, refer to the [troubleshooting sysbox-deploy-k8s](troubleshoot-k8s.md) doc.
