# Sysbox User Guide: Installation in Kubernetes Clusters

This document describes how to install Sysbox on a Kubernetes cluster (i.e., to
deploy pods with Sysbox).

If you are installing Sysbox on a regular host (i.e., not a Kubernetes host),
follow [these instructions](install-package.md) instead.

## Contents

-   [Kubernetes Version Requirements](#kubernetes-version-requirements)
-   [Kubernetes Worker Node Requirements](#kubernetes-worker-node-requirements)
-   [Installation](#installation)
-   [Installation Manifests](#installation-manifests)
-   [Pod Deployment](#pod-deployment)
-   [Uninstallation](#uninstallation)
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

## Installation Manifests

The K8s manifests used for setting up Sysbox can be found [here](../../sysbox-k8s-manifests).

## Pod Deployment

Once Sysbox is installed, you can deploy pods with it easily. See
[here](deploy.md#deploying-pods-with-kubernetes--sysbox) for more on this.

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
