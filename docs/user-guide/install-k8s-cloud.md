# Sysbox User Guide: Installing Sysbox on Cloud-Based Kubernetes Clusters

## Contents

*   [GKE](#gke)

## GKE

1.  Create a cluster with Kubernetes v1.20 (available via the "Rapid" and
    "Regular" channel options).

2.  Create the K8s worker nodes where Sysbox will be installed using the "Ubuntu
    with Containerd" image template.

    - Ensure the nodes have a minimum of 4 vCPUs each.

    - Do NOT enable secure-boot on the nodes, as this prevents the
      sysbox-deploy-k8s daemonset from installing the [shiftfs module](design.md#ubuntu-shiftfs-module)
      into the kernel. This module is usually present in Ubuntu desktop and
      server images, but not present in Ubuntu cloud images, so the
      sysbox-deploy-k8s daemonset must install it.

3.  Label the nodes and deploy the CRI-O and Sysbox installation daemonsets as shown in
    the [Sysbox installation on K8s clusters instructions](install-k8s.md).

**NOTES:**

* On GKE, do not install CRI-O on the K8s node where the
  `konnectivity-agent-autoscaler` pod is running. There is a problem that
  prevents this pod from running properly with CRI-O.
