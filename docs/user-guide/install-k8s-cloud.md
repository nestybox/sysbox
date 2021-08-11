# Sysbox User Guide: Installing Sysbox on Cloud-Based Kubernetes Clusters

## Contents

-   [Google Kubernetes Engine (GKE)](#google-kubernetes-engine-gke)
-   [AWS Elastic Kubernetes Service (EKS)](#aws-elastic-kubernetes-service-eks)

## Google Kubernetes Engine (GKE)

1.  Create a cluster with Kubernetes v1.20 (available via the "Rapid" and
    "Regular" channel options).

2.  Create the K8s worker nodes where Sysbox will be installed using the "Ubuntu
    with Containerd" image template.

    -   Ensure the nodes have a minimum of 4 vCPUs each.

    -   Do NOT enable secure-boot on the nodes, as this prevents the
        sysbox-deploy-k8s daemonset from installing the [shiftfs module](design.md#ubuntu-shiftfs-module)
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
