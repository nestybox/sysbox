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

-   [Kubernetes Distro Requirements](#kubernetes-distro-requirements)
-   [Kubernetes Version Requirements](#kubernetes-version-requirements)
-   [Kubernetes Worker Node Requirements](#kubernetes-worker-node-requirements)
-   [CRI-O Requirement](#cri-o-requirement)
-   [Installation of Sysbox](#installation-of-sysbox)
-   [Installation of Sysbox Enterprise Edition (Sysbox-EE)](#installation-of-sysbox-enterprise-edition-sysbox-ee)
-   [Installation Manifests](#installation-manifests)
-   [Pod Deployment](#pod-deployment)
-   [Limitations](#limitations)
-   [Uninstallation](#uninstallation)
-   [Upgrading Sysbox or Sysbox Enterprise](#upgrading-sysbox-or-sysbox-enterprise)
-   [Replacing Sysbox with Sysbox Enterprise](#replacing-sysbox-with-sysbox-enterprise)
-   [Troubleshooting](#troubleshooting)

## Kubernetes Distro Requirements

In general Sysbox works in all Kubernetes distros (it's agnostic to them), as
long as the Kubernetes version and node requirements are met (see next
sections).

Having said that, at the moment the Sysbox installation process described in
this document has only been tested in the following scenarios:

| Kubernetes Distros    |  Tested OS Distros                          | Cluster Setup Notes |
| --------------------- | ------------------------------------------ | ------------------- |
| Kubernetes (regular)  |  Ubuntu Bionic / Focal, Flatcar            | [(1)](install-k8s-distros.md#kubernetes-regular) |
| Amazon EKS            |  Ubuntu Focal                              | [(2)](install-k8s-distros.md#aws-elastic-kubernetes-service-eks) |
| Azure AKS             |  Ubuntu Bionic with Containerd             | [(3)](install-k8s-distros.md#azure-kubernetes-service-aks) |
| Google GKE            |  Ubuntu-Containerd or Ubuntu-Docker images | [(4)](install-k8s-distros.md#google-kubernetes-engine-gke) |
| Rancher RKE           |  Ubuntu Focal                              | [(5)](install-k8s-distros.md#rancher-kubernetes-engine-rke) |
| Rancher RKE2          |  Ubuntu Focal                              | [(6)](install-k8s-distros.md#rancher-next-gen-kubernetes-engine-rke2) |
| Kinvolk Lokomotive    |  Flatcar                                   | [(7)](install-k8s-distros.md#kinvolk-lokomotive) |

Regardless of the elected Kubernetes distro and the pre-existing container
runtime (i.e. containerd or docker), the Sysbox installation method presented
below is the same: via the **"sysbox-deploy-k8s"** daemonset. This daemonset
installs CRI-O and Sysbox on the desired Kubernetes nodes. Other nodes are left
untouched.

## Kubernetes Version Requirements

Sysbox is supported on the following Kubernetes versions:

-   Kubernetes v1.27.\*
-   Kubernetes v1.28.\*
-   Kubernetes v1.29.\*
-   Kubernetes v1.30.\*

For consistency purposes, we strive to match the official Kubernetes' release
cadence as closely as possible. This translates into previously supported
releases being eventually considered 'end-of-life' (EOL).

EOL releases:

-   Kubernetes v1.20.\*
-   Kubernetes v1.21.\*
-   Kubernetes v1.22.\*
-   Kubernetes v1.23.\*
-   Kubernetes v1.24.\*
-   Kubernetes v1.25.\*
-   Kubernetes v1.26.\*

Other versions of Kubernetes are not supported.

## Kubernetes Worker Node Requirements

Prior to installing Sysbox, ensure each K8s worker node where you will install
Sysbox meets the following requirement:

-   The node's OS must be Ubuntu Jammy, Focal, or Bionic (with a 5.4+ kernel).

-   The node's platform architecture must match one of the Sysbox's [supported architectures](../arch-compat.md).

-   We recommend a minimum of 4 CPUs (e.g., 2 cores with 2 hyperthreads) and 4GB
    of RAM in each worker node. Though this is not a hard requirement, smaller
    configurations may slow down Sysbox.

## CRI-O Requirement

Sysbox currently requires the [CRI-O](https://cri-o.io/) runtime as it includes
support for deploying Kubernetes pods with the Linux user namespace (for
stronger isolation). Containerd does not yet include this support.

**NOTE: You don't need to install CRI-O prior to installing Sysbox. The Sysbox
installer for Kubernetes (see next section) automatically installs CRI-O on the
desired Kubernetes worker nodes and configures the Kubelet appropriately.**

## Installation of Sysbox

**NOTE: These instructions work generally in all Kubernetes clusters. For
additional instructions specific to a Kubernetes distribution, refer to
[this](install-k8s-distros.md) document.**

Installation is easily done via a daemonset called "sysbox-deploy-k8s", which
installs the Sysbox and CRI-O binaries onto the desired K8s nodes and performs
all associated config.

Steps:

```console
kubectl label nodes <node-name> sysbox-install=yes
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-install.yaml
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

-   If you hit problems, refer to the [troubleshooting sysbox-deploy-k8s](troubleshoot-k8s.md) doc.

## Installation of Sysbox Enterprise Edition (Sysbox-EE) [DEPRECATED]

Sysbox Enterprise Edition (Sysbox-EE) is the enterprise version of Sysbox, with
improved security, functionality, performance, life-cycle, and Nestybox support.

The installation for Sysbox Enterprise Edition (Sysbox-EE) in Kubernetes
clusters is exactly the same as for Sysbox (see [prior section](#installation-of-sysbox)),
except that you use the `sysbox-ee-install.yaml` instead of `sysbox-install.yaml`:

```console
kubectl label nodes <node-name> sysbox-install=yes
kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-ee-install.yaml
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

The number of Sysbox pods that can be deployed on a node depends on many
factors such as the number of CPUs on the node, the memory size on the node, the
the amount of storage, the type of workloads running in the pods, resource
limits on the pod, etc.)

See [here](limitations.md#kubernetes-restrictions) for further info on sysbox
pod limitations.

## Uninstallation

To uninstall Sysbox:

```console
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-install.yaml
sleep 30

kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-uninstall.yaml
sleep 60

kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-uninstall.yaml
```

For Sysbox Enterprise, use the `sysbox-ee-cleanup-k8s.yaml` instead of the `sysbox-cleanup-k8s.yaml`:

```console
kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-ee-install.yaml
sleep 30

kubectl apply -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-ee-uninstall.yaml
sleep 60

kubectl delete -f https://raw.githubusercontent.com/nestybox/sysbox/master/sysbox-k8s-manifests/sysbox-ee-uninstall.yaml
```

NOTES:

-   Make sure to stop all K8s pods deployed with Sysbox prior to uninstalling
    Sysbox.

-   The uninstallation will temporarily disrupt all pods on the nodes where CRI-O
    and Sysbox were installed, for up to 1 minute, as they require the kubelet to
    restart.

-   The 'sleep' instructions above ensure that kubelet has a chance to launch
    and execute the daemonsets before the subsequent step.

## Upgrading Sysbox or Sysbox Enterprise [DEPRECATED]

The [sysbox-install manifest](../../sysbox-k8s-manifests/sysbox-install.yaml) points to
a container image that carries the Sysbox binaries that are installed
onto the Kubernetes worker nodes. The same applies to the
[sysbox-ee-install manifest](../../sysbox-k8s-manifests/sysbox-ee-install.yaml) for Sysbox Enterprise.

Nestybox regularly updates these manifests to point to the container images
carrying the latest Sysbox and Sysbox Enterprise releases.

To upgrade Sysbox, [first uninstall Sysbox](#uninstallation)
and [re-install](#installation-of-sysbox) the updated version.

**NOTE:** You must stop all Sysbox pods on the K8s cluster prior to uninstalling
Sysbox.

## Replacing Sysbox with Sysbox Enterprise [DEPRECATED]

Sysbox Enterprise Edition (Sysbox-EE) is a drop-in replacement for Sysbox.

If you have a host with Sysbox and wish to install Sysbox Enterprise in it,
simply [uninstall Sysbox](#uninstallation) and
[install Sysbox Enterprise](#installation-of-sysbox-enterprise-edition-sysbox-ee)
from your K8s clusters as described above.

**NOTE:** While it's possible to have some worker nodes with Sysbox and others
with Sysbox Enterprise, be aware that the installation daemonsets are designed
to install one or the other, so it's better to install Sysbox or Sysbox
Enterprise on a given Kubernetes cluster, never both.

## Troubleshooting

If you hit problems, refer to the [troubleshooting sysbox-deploy-k8s](troubleshoot-k8s.md) doc.
