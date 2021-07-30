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

* Do not install CRI-O on the K8s node where the
  `konnectivity-agent-autoscaler` pod is running. There is a problem that
  prevents this pod from running properly with CRI-O.

* During the installation of CRI-O, the Kubelet is restarted on all nodes where
  CRI-O is installed (i.e., nodes labeled with `crio-install=yes`). This forces
  all pods on the nodes to be recreated. During the recreation, sometimes a few
  daemonset pods in the "kube-system" namespace fail to come up. We are
  investigating the reason. As a work-around, delete the pod and it will
  automatically be recreated by the K8s control plane, usually without problem.

* The installation of CRI-O on a K8s node causes the K8s node to enter the "not
  ready" state temporarily. This condition should not last for more than 2
  minutes. Same applies to the installation of Sysbox on a K8s node. It's
  important that the K8s node not remain in the "not ready" state for too long
  (e.g., > 10 minutes), as otherwise the GKE K8s control plane will destroy and
  recreate the node automatically, further delaying the installation process.
