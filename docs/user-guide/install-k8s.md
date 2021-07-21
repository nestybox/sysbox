# Sysbox User Guide: Installation in Kubernetes Clusters \[ v0.4.0+ ]

Starting with Sysbox v0.4.0, it's possible to install Sysbox in Kubernetes
clusters (i.e., to deploy pods with Sysbox).

Such pods are strongly isolated from the host and can seamlessly run
micro-services or system-level workloads such as systemd, Docker, and even
Kubernetes in them (much like VMs).

This document describes how to install Sysbox on a Kubernetes cluster. If you
are installing Sysbox on a regular host (i.e., not a Kubernetes host), follow
[these instructions](install-package.md) instead.

## Contents

-   [Kubernetes Version Requirements](#kubernetes-version-requirements)
-   [Kubernetes Worker Node Requirements](#kubernetes-worker-node-requirements)
-   [Installation of Sysbox](#installation-of-sysbox)
-   [Installation of Sysbox Enterprise Edition (Sysbox-EE)](#installation-of-sysbox-enterprise-edition-sysbox-ee)
-   [Installation Manifests](#installation-manifests)
-   [Pod Deployment](#pod-deployment)
-   [Uninstallation of Sysbox or Sysbox Enterprise](#uninstallation-of-sysbox-or-sysbox-enterprise)
-   [Uninstallation of CRI-O](#uninstallation-of-cri-o)
-   [Upgrading Sysbox or Sysbox Enterprise](#upgrading-sysbox-or-sysbox-enterprise)
-   [Replacing Sysbox with Sysbox Enterprise](#replacing-sysbox-with-sysbox-enterprise)
-   [Troubleshooting](#troubleshooting)

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

## Installation of Sysbox

**NOTE: These instructions work generally in all Kubernetes clusters. For
additional instructions specific to cloud-based Kubernetes clusters, see
[here](install-k8s-cloud.md).**

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

Then deploy pods with Sysbox [see next section](#pod-deployment).

NOTES:

-   The installation will temporarily disrupt all pods on the K8s worker nodes
    where CRI-O and Sysbox were installed, for up to 1 minute, as they require
    the kubelet to restart.

-   Sysbox can be installed in all or some of the Kubernetes cluster worker nodes,
    according to your needs.

-   Installing Sysbox on a node does not imply all pods on the node are deployed
    with Sysbox. You can choose which pods use Sysbox via the pod's spec (see
    [Pod Deployment](#pod-deployment) below). Pods that don't use Sysbox
    continue to use the default low-level runtime (i.e., the OCI runc) or any
    other runtime you choose.

-   Pods deployed with Sysbox are managed via K8s just like any other pods; they
    can live side-by-side with non Sysbox pods and can communicate with them
    according to your K8s networking policy.

-   If you hit problems, refer to the [troubleshooting sysbox-deploy-k8s](troubleshoot-k8s.md) doc.

## Installation of Sysbox Enterprise Edition (Sysbox-EE)

Sysbox Enterprise Edition (Sysbox-EE) is the enterprise version of Sysbox, with
improved security, functionality, performance, life-cycle, and Nestybox support.

The installation for Sysbox Enterprise Edition (Sysbox-EE) in Kubernetes
clusters is exactly the same as for Sysbox (see [prior section](#installation-of-sysbox)),
except that you use the `sysbox-ee-deploy-k8s.yaml` instead of `sysbox-deploy-k8s.yaml`:

```console
kubectl label nodes <node-name> sysbox-install=yes
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/sysbox-deploy-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-ee-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/runtime-class/sysbox-runtimeclass.yaml
```

**NOTE:** either Sysbox or Sysbox Enterprise must be installed on a given host, never both.

## Installation Manifests

The K8s manifests used for setting up Sysbox can be found [here](../../sysbox-k8s-manifests).

## Pod Deployment

Once Sysbox is installed, you can deploy pods with it easily. See
[here](deploy.md#deploying-pods-with-kubernetes--sysbox) for more on this.

## Uninstallation of Sysbox or Sysbox Enterprise

To uninstall Sysbox:

```console
kubectl delete runtimeclass sysbox-runc
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/sysbox-deploy-rbac.yaml
```

For Sysbox Enterprise, use the `sysbox-ee-cleanup-k8s.yaml` instead of the `sysbox-cleanup-k8s.yaml`:

```console
kubectl delete runtimeclass sysbox-runc
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-ee-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-ee-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/sysbox-deploy-rbac.yaml
```

## Uninstallation of CRI-O

To uninstall CRI-O:

```console
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/crio-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/crio-cleanup-k8s.yaml

sleep 10

kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/crio-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/crio-deploy-rbac.yaml
```

NOTES:

-   Make sure to stop all K8s pods deployed with Sysbox prior to uninstalling
    Sysbox.

-   The uninstallation will temporarily disrupt all pods on the nodes where CRI-O
    and Sysbox were installed, for up to 1 minute, as they require the kubelet to
    restart.

-   The sleep instruction above is to ensure that kubelet has a chance to launch
    the 'cleanup' daemonset before it is removed in the next step.

## Upgrading Sysbox or Sysbox Enterprise

The [sysbox-deploy-k8s manifest](../../sysbox-k8s-manifests/daemonset/sysbox-deploy-k8s.yaml) points to
a container image that carries the Sysbox binaries, which the daemonset then
installs onto the Kubernetes worker nodes. The same applies to the
[sysbox-ee-deploy-k8s manifest](../../sysbox-k8s-manifests/daemonset/sysbox-ee-deploy-k8s.yaml) for Sysbox Enterprise.

Nestybox regularly updates these manifests to point to the container images
carrying the latest Sysbox and Sysbox Enterprise releases.

To upgrade Sysbox, [first uninstall Sysbox](#uninstallation-of-sysbox-or-sysbox-enterprise)
and [re-install](#installation-of-sysbox) the updated version.

**NOTE:** You must stop all Sysbox pods on the K8s cluster prior to uninstalling
Sysbox.

## Replacing Sysbox with Sysbox Enterprise

Sysbox Enterprise Edition (Sysbox-EE) is a drop-in replacement for Sysbox.

If you have a host with Sysbox and wish to install Sysbox Enterprise in it,
simply [uninstall Sysbox](#uninstallation-of-sysbox-or-sysbox-enterprise) and
[install Sysbox Enterprise](#installation-of-sysbox-enterprise-edition-sysbox-ee)
from your K8s clusters as described above.

**NOTE:** While it's possible to have some worker nodes with Sysbox and others
with Sysbox Enterprise, be aware that the installation & cleanup daemonsets are
designed to install one or the other, so it's better to install Sysbox or Sysbox
Enterprise on a given Kubernetes cluster, never both.

## Troubleshooting

If you hit problems, refer to the [troubleshooting sysbox-deploy-k8s](troubleshoot-k8s.md) doc.
