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
-   [Limitations](#limitations)
-   [Uninstallation of Sysbox or Sysbox Enterprise](#uninstallation-of-sysbox-or-sysbox-enterprise)
-   [Upgrading Sysbox or Sysbox Enterprise](#upgrading-sysbox-or-sysbox-enterprise)
-   [Replacing Sysbox with Sysbox Enterprise](#replacing-sysbox-with-sysbox-enterprise)
-   [Troubleshooting](#troubleshooting)

## Kubernetes Version Requirements

Sysbox is only supported on Kubernetes v1.20.\* at this time.

The reason for this is that Sysbox currently requires the presence of the CRI-O
runtime v1.20, as the latter introduces support for "rootless pods" (i.e., pods
that use the Linux user-namespace). Since the version of CRI-O and K8s must match, the
K8s version must also be v1.20.\*.

The Sysbox installation steps below automatically install CRI-O on the Kubernetes nodes.

## Kubernetes Worker Node Requirements

Prior to installing Sysbox, ensure each K8s worker node where you will install
Sysbox meets the following requirement:

-   The node's OS must be Ubuntu Focal or Bionic (with a 5.0+ kernel).

-   We recommend a minimum of 4 CPUs (e.g., 2 cores with 2 hyperthreads) and 4GB
    of RAM in each worker node. Though this is not a hard requirement, smaller
    configurations may slow down Sysbox.

## Installation of Sysbox

**NOTE: These instructions work generally in all Kubernetes clusters. For
additional instructions specific to cloud-based Kubernetes clusters, see
[here](install-k8s-cloud.md).**

Installation is done via a daemonset called "sysbox-deploy-k8s", which installs
the CRI-O and Sysbox binaries onto the desired K8s nodes and performs all
associated config.

Steps:

```console
kubectl label nodes <node-name> sysbox-install=yes
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/sysbox-deploy-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/runtime-class/sysbox-runtimeclass.yaml
```

**NOTE:** the above step will restart the Kubelet on all nodes where Sysbox is
being installed, causing all pods on the node to be stopped and
re-created. Depending on the number of pods, this process can take anywhere from
30 secs to 2 minutes. Wait for this process to complete before proceeding.

Once Sysbox installation completes, you can proceed to deploy pods with Sysbox
as shown in section [Pod Deployment](#pod-deployment).

Additional notes:

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

-   In the past, we used a separate daemonset to install CRI-O. That daemonset
    is now deprecated, though it can be found [here](../../sysbox-k8s-manifests/daemonset/crio).
    There is no need to use it any more, as the sysbox-deploy-k8s daemonset now
    installs both CRI-O and Sysbox on the node (it's faster and simpler to use
    only one daemonset).

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

Once Sysbox is installed it's easy to deploy pods with it.

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

See [here](deploy.md#deploying-pods-with-kubernetes--sysbox) for more info.

## Limitations

Pods launched with the Sysbox Community Edition are **limited to \*\*16 pods per worker node\*\***.

Once this limit is reached, new pods scheduled on the node will remain in the
"ContainerCreating" state. Such pods need to be terminated and re-created once
there is sufficient capacity on the node.

#### ** --- Sysbox-EE Feature Highlight --- **

With Sysbox Enterprise (Sysbox-EE) this limitation is removed, as it's designed
for greater scalability. Thus, you can launch as many pods as will fit on the
Kubernetes node, allowing you to get the best utilization of the hardware.

Note that the number of pods that can be deployed on a node depends on many
factors such as the number of CPUs on the node, the memory size on the node, the
the amount of storage, the type of workloads running in the pods, resource
limits on the pod, etc.)


See [here](limitations.md#kubernetes-restrictions) for further info on sysbox
pod limitations.

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
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-ee-deploy-k8s.yaml
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-ee-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/daemonset/sysbox-ee-cleanup-k8s.yaml
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/rbac/sysbox-deploy-rbac.yaml
```

NOTES:

-   Make sure to stop all K8s pods deployed with Sysbox prior to uninstalling
    Sysbox.

-   The uninstallation will temporarily disrupt all pods on the nodes where CRI-O
    and Sysbox were installed, for up to 1 minute, as they require the kubelet to
    restart.

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
