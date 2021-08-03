# DEPRECATION NOTICE

***

**THE KUBERNETES MANIFESTS IN THIS DIRECTORY (CRIO-DEPLOY-K8S AND
CRIO-CLEANUP-K8S) ARE NOW DEPRECATED.**

**DO NOT USE THESE DAEMONSETS IF YOU WISH TO INSTALL SYSBOX ON A HOST; INSTEAD,
USE ONLY THE SYSBOX-DEPLOY-K8S DAEMONSET WHICH WILL INSTALL BOTH CRI-O AND
SYSBOX ON THE HOST.**

***

The crio-deploy-k8s daemenoset in this directory was previously needed to
install CRI-O on a Kubernetes node, in preparation to installing Sysbox on the
node using the separate sysbox-deploy-k8s daemonset. This is no longer the case,
as the latest version of the sysbox-deploy-k8s daemonset installs both CRI-O and
Sysbox (in order to simplify and significantly speed up the installation
process).

You can still use this daemonset if you wish to only install CRI-O on a
Kubernetes node (i.e., without installing Sysbox). However, note that there are
no plans to update this daemonset for newer versions of CRI-O (it currently
installs CRI-O v1.20).
