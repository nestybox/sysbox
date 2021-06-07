# Sysbox User Guide: Container Deployment

This document shows how to deploy containers with Sysbox. It assumes
Sysbox is already [installed](install.md).

To deploy containers with Sysbox, you typically use a container manager or
orchestrator (e.g., Docker or Kubernetes) or any higher level tools built on top
of these (e.g., Docker compose).

Users **do not** normally interact with Sysbox directly, as it uses a low-level
interface (though this is possible as shown [below](#deploying-containers-with-sysbox-runc-directly)
for reference).

## Contents

-   [Deploying containers with Docker + Sysbox](#deploying-containers-with-docker--sysbox)
-   [Deploying containers with Kubernetes + Sysbox](#deploying-containers-with-kubernetes--sysbox)
-   [Deploying containers with sysbox-runc directly](#deploying-containers-with-sysbox-runc-directly)
-   [Using Other Container Managers](#using-other-container-managers)

## Deploying containers with Docker + Sysbox

Simply add the `--runtime=sysbox-runc` flag in the `docker run` command:

```console
$ docker run --runtime=sysbox-runc --rm -it nestybox/ubuntu-bionic-systemd-docker
root@my_cont:/#
```

You can choose any container image of your choice, whether that image carries a
single microservice that you wish to run with strong isolation (via the Linux
user-namespace), or whether it carries a full OS environment with systemd,
Docker, etc. (as the container image in the above example does).

Nestybox has several reference images in our [Dockerhub registry](https://hub.docker.com/u/nestybox).

The [Sysbox Quickstart Guide](../quickstart/README.md) and [Nestybox blog](https://blog.nestybox.com)
have several examples.

If you wish, you can configure Sysbox as the default runtime for Docker. This
way you don't have to use the `--runtime` flag every time. To do this,
see [here](install-package.md#configuring-dockers-default-runtime-to-sysbox).

**NOTE:** Almost all Docker functionality works with Sysbox, but there are a few
exceptions. See the [Sysbox limitations doc](limitations.md) for further info.

## Deploying containers with Kubernetes + Sysbox

To deploy a Kubernetes pod with Sysbox, use a pod spec such as this one:

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

There are two directives in the pod spec that tie it to Sysbox:

-   `runtimeClassName: sysbox-runc` tells Kubernetes to use the Sysbox runtime to
    deploy the pod. This assumes the Sysbox runtime class resource has been
    applied to the cluster as shown [here](install-k8s.md).

-   `io.kubernetes.cri-o.userns-mode: "auto:size=65536"` tells CRI-O to
    enable the Linux user-namespace on the pod and auto assign ID mappings
    to it. This is necessary to run the pod with Sysbox.

You can choose any container image of your choice; Nestybox has several
reference images in our [Dockerhub registry](https://hub.docker.com/u/nestybox).

## Deploying containers with sysbox-runc directly

**NOTE: This is not the usual way to deploy containers with Sysbox as the
interface is low-level (it's defined by the OCI runtime spec). However, we
include it here for refence because it's useful when wishing to control the
configuration of the system container at the lowest level.**

As the root user, follow these steps:

1.  Create a rootfs image for the system container:

```console
# mkdir /root/syscontainer
l# cd /root/syscontainer
# mkdir rootfs
# docker export $(docker create debian:latest) | tar -C rootfs -xvf -
```

2.  Create the OCI spec (i.e., `config.json` file) for the system container:

```console
# sysbox-runc spec
```

3.  Launch the system container.

Choose a unique name for the container and run:

```console
# sysbox-runc run my_syscontainer
```

Use `sysbox-runc --help` command for help on all commands supported.

A couple of tips:

-   In step (1):

    -   If the `config.json` does not specify the Linux user namespace, the
        container's rootfs should be owned by `root:root`. This also requires that
        the [shiftfs module](design.md#ubuntu-shiftfs-module) be present in the
        kernel.

    -   If the `config.json` does specify the Linux user namespace and associated
        user-ID and group-ID mappings, the container's rootfs should be owned
        by the corresponding user-ID and group-ID. In this case, the presence of
        the shiftfs module is not required.

-   Feel free to modify the system container's `config.json` to your needs. But
    note that Sysbox ignores a few of the OCI directives in this file (refer to
    the [Sysbox design document](design.md#sysbox-oci-compatibility) for details).

## Using Other Container Managers

We currently only support the above methods to run containers with
Sysbox. However, other OCI-based container managers will most likely work.
