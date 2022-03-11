# Sysbox User Guide: Kubernetes Distro-Specific Installation Instructions

This document contains info on how to setup a Kubernetes cluster to install
Sysbox. Each section covers a different Kubernetes distro.

## Contents

-   [Kubernetes (regular)](#kubernetes-(regular))
-   [AWS Elastic Kubernetes Service (EKS)](#aws-elastic-kubernetes-service-eks)
-   [Azure Kubernetes Service (AKS)](#azure-kubernetes-service-aks)
-   [Google Kubernetes Engine (GKE)](#google-kubernetes-engine-gke)
-   [Rancher Kubernetes Engine (RKE)](#rancher-kubernetes-engine-rke)
-   [Rancher Next-Gen Kubernetes Engine (RKE2)](#rancher-next-gen-kubernetes-engine-rke2)
-   [Kinvolk Lokomotive](#kinvolk-lokomotive)


## Kubernetes (regular)

1.  Create a cluster through [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
    or any equivalent tool. Take into account the Sysbox requirements described
    [here](install-k8s.md#kubernetes-worker-node-requirements).

2.  Once the cluster is created, proceed to install Sysbox as shown
    [here](install-k8s.md).

## AWS Elastic Kubernetes Service (EKS)

1.  Create the EKS cluster using an Ubuntu-based AMI for the K8s worker nodes.

    -   Ensure the nodes have a minimum of 4 vCPUs each.

An easy way to do this is using [eksctl](https://eksctl.io/), the official CLI
for AWS EKS.

For example, the following cluster configuration yaml creates an EKS cluster with
Kubernetes v1.20 and a [managed node-group](https://docs.aws.amazon.com/eks/latest/userguide/eks-compute.html)
composed of 3 Ubuntu-based nodes (t3.xlarge instances):

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: my-cluster
  region: us-west-2
  version: "1.20"

managedNodeGroups:
  - name: ubuntu-nodes
    amiFamily: Ubuntu2004
    instanceType: t3.xlarge
    desiredCapacity: 3
    minSize: 3
    maxSize: 5
    volumeSize: 200
    ssh:
      allow: true
      publicKeyName: awsEksKey
```

First create the `awsEksKey`:

```console
aws ec2 create-key-pair --region us-west-2 --key-name awsEksKey
```

And then create the cluster with:

```console
eksctl create cluster --config-file=<your-cluster-config.yaml>

2021-08-11 02:16:41 [ℹ]  eksctl version 0.59.0
2021-08-11 02:16:41 [ℹ]  using region us-west-2
...
2021-08-11 02:43:15 [✔]  EKS cluster "my-cluster2" in "us-west-2" region is ready
```

The cluster creation process on EKS takes a while (~25 min!).

2.  Once the cluster is created, proceed to install Sysbox as shown
    [here](install-k8s.md).

**NOTES:**

-   The installation of Sysbox (which also installs CRI-O on the desired K8s
    worker nodes) takes between 2->3 minutes on EKS.

    -   You can view it's progress by looking at the logs of the sysbox-deploy-k8s pod.

```console
$ kubectl -n kube-system logs -f pod/sysbox-deploy-<pod-id>

Adding K8s label "crio-runtime=installing" to node
...
The k8s runtime on this node is now CRI-O.
Sysbox installation completed.
Done.
```

-   If the installation takes significantly longer, something is likely
    wrong. See [here](troubleshoot-k8s.md) for troubleshoot info.

## Azure Kubernetes Service (AKS)

1.  Create a cluster by following the official [documentation](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough).

2.  Sysbox can be properly installed over the K8s worker nodes created by
AKS by default (i.e., Ubuntu-Bionic + Containerd). However, the default
hardware specs (2 vCPU) are not ideal to run Sysbox pods on, so ensure that
the nodes have a minimum of 4 vCPUs each.

**NOTES:**

-   The installation of Sysbox (which also installs CRI-O on the desired K8s
    worker nodes) takes between 1->2 minutes on AKS.

    -   If it takes significantly longer than this, something is likely wrong. See
        [here](troubleshoot-k8s.md) for troubleshoot info.

## Google Kubernetes Engine (GKE)

1.  Create a cluster with Kubernetes v1.20 or v1.21.

2.  Create the K8s worker nodes where Sysbox will be installed using the "Ubuntu
    with Containerd" image templates.

    -   Ensure the nodes have a minimum of 4 vCPUs each.

    -   Do NOT enable secure-boot on the nodes, as this prevents the
        sysbox-deploy-k8s daemonset from installing the [shiftfs module](design.md#shiftfs-module)
        into the kernel. This module is usually present in Ubuntu desktop and
        server images, but not present in Ubuntu cloud images, so the
        sysbox-deploy-k8s daemonset must install it.

3.  Label the nodes and deploy the Sysbox installation daemonset as shown in
    the [Sysbox installation on K8s clusters instructions](install-k8s.md).

**NOTES:**

-   The installation of Sysbox (which also installs CRI-O on the desired K8s
    worker nodes) takes between 1->2 minutes on GKE.

    -   If it takes significantly longer than this, something is likely wrong. See
        [here](troubleshoot-k8s.md) for troubleshoot info.

## Rancher Kubernetes Engine (RKE)

1.  Create a cluster through the [Rancher](https://rancher.com/quick-start/) UI,
    or by making use of the RKE provisioning [tool](https://rancher.com/products/rke/).
    Take into account the Sysbox node requirements described
    [here](install-k8s.md#kubernetes-worker-node-requirements).

2.  Once the cluster is fully operational, proceed to install Sysbox as shown
    [here](install-k8s.md).

**NOTES:**

-   The installation of Sysbox (which also installs CRI-O on the desired K8s
    worker nodes) takes between 1->2 minutes on RKE clusters.

-   Upon successful installation of Sysbox, all the K8s PODs will be re-spawned
    through CRI-O. However, the control-plane components (e.g., kubelet) created as
    Docker containers by the RKE provisioning tool, will continue to be handled by
    docker.

## Rancher Next-Gen Kubernetes Engine (RKE2)

1.  Create an RKE2 cluster through the [Rancher](https://rancher.com/quick-start/)
    UI (must be running Rancher v2.6+), or by making use of the RKE2 provisioning
    [tool](https://docs.rke2.io). Take into account the Sysbox node requirements
    described [here](install-k8s.md#kubernetes-worker-node-requirements).

2.  Once the cluster is fully operational, proceed to install Sysbox as shown
    [here](install-k8s.md).

**NOTES:**

-   The installation of Sysbox (which also installs CRI-O on the desired K8s
    worker nodes) takes between 1->2 minutes on RKE2 clusters.

## Kinvolk Lokomotive

1.  Create a Lokomotive cluster as described in the [documentation](https://kinvolk.io/docs/lokomotive/0.9/installer/lokoctl/).
Take into account the Sysbox node requirements described [here](install-k8s.md#kubernetes-worker-node-requirements),
and the fact that Lokomotive runs atop Flatcar Container Linux distribution,
which is only [supported](../distro-compat.md) in the Sysbox-EE offering.

2.  Once the cluster is fully operational, proceed to install Sysbox as shown
    [here](install-k8s.md).

**NOTES:**

-   The current Sysbox K8s installer does not fully support Lokomotive's
"self-hosted" approach to manage K8s clusters. In particular, Sysbox is
currently unable to interact with the two different sets of Kubelet processes
created by Lokomotive. That is, Sysbox is only capable of configuring the
[bootstrap](https://kinvolk.io/docs/lokomotive/latest/how-to-guides/update-bootstrap-kubelet/)
Kubelet process. Thereby, for the proper operation of Sysbox within a Lokomotive
cluster, the default Kubelet daemon-set must be disabled or eliminated with the
following (or equivalent) instruction:

```console
$ kubectl delete -n kube-system daemonset.apps/kubelet --cascade=true
```

-   Sysbox installation in a Lokomotive cluster is strikingly fast -- usually
doesn't exceed 20-30 seconds. This is just a consequence of the fact that
`sysbox-ee-deploy-k8s` daemon-set prepackages all the required dependencies.
