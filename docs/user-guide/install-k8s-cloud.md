# Sysbox User Guide: Installing Sysbox on Cloud-Based Kubernetes Clusters

## Contents

*   [GKE](#gke)

## GKE

1.  Create a cluster with Kubernetes v1.20 (available via the "Rapid Channel" option).

2.  Create the K8s worker nodes where Sysbox will be installed using the "Ubuntu
    with Containerd" image template.

3.  Label the nodes and deploy the CRI-O and Sysbox installation daemonsets as shown in
    the [Sysbox installation on K8s clusters instructions](install-k8s.md).

**NOTE: On GKE, do not install CRI-O on the K8s node where the
`konnectivity-agent-autoscaler` pod is running. There is a problem that prevents
this pod from running properly with CRI-O.**
