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
-   [Deploying Pods with Kubernetes + Sysbox](#deploying-pods-with-kubernetes--sysbox)
-   [Sysbox Container Images](#sysbox-container-images)
-   [Mounting Storage into Sysbox Containers (or Pods)](#mounting-storage-into-sysbox-containers-or-pods)
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

The [Sysbox Quickstart Guide](../quickstart/README.md) and [Nestybox blog](https://blog.nestybox.com)
have several examples.

If you wish, you can configure Sysbox as the default runtime for Docker. This
way you don't have to use the `--runtime` flag every time. To do this,
see [here](install-package.md#configuring-dockers-default-runtime-to-sysbox).

**NOTE:** Almost all Docker functionality works with Sysbox, but there are a few
exceptions. See the [Sysbox limitations doc](limitations.md) for further info.

## Deploying Pods with Kubernetes + Sysbox

Assuming Sysbox is [installed](install-k8s.md) on the Kubernetes cluster,
deploying pods with Sysbox is easy: you only need a couple of things in the pod
spec.

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

There are two key pieces of the pod's spec that tie it to Sysbox:

-   **"runtimeClassName":** Tells K8s to deploy the pod with Sysbox (rather than the
    default OCI runc). The pods will be scheduled only on the nodes that support
    Sysbox.

-   **"io.kubernetes.cri-o.userns-mode":** Tells CRI-O to launch this as a rootless
    pod (i.e., root user in the pod maps to an unprivileged user on the host)
    and to allocate a range of 65536 Linux user-namespace user and group
    IDs. This is required for Sysbox pods.

Also, for Sysbox pods you typically want to avoid sharing the process (pid)
namespace between containers in a pod. Thus, avoid setting
`shareProcessNamespace: true` in the pod's spec, especially if the pod carries
systemd inside (as otherwise systemd won't be pid 1 in the pod and will fail).

Depending on the size of the pod's image, it may take several seconds for the
pod to deploy on the node. Once the image is downloaded on a node however,
deployment should be very quick (few seconds).

Here is a similar example, but this time using a Kubernetes Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: syscont-deployment
  labels:
    app: syscont
spec:
  replicas: 4
  selector:
    matchLabels:
      app: syscont
  template:
    metadata:
      labels:
        app: syscont
      annotations:
        io.kubernetes.cri-o.userns-mode: "auto:size=65536"
    spec:
      runtimeClassName: sysbox-runc
      containers:
      - name: ubu-bio-systemd-docker
        image: registry.nestybox.com/nestybox/ubuntu-bionic-systemd-docker
        command: ["/sbin/init"]
```

### Sysbox Pod Limitations

See the [limitations section](limitations.md#kubernetes-restrictions) of the
User Guide.

## Sysbox Container Images

The prior examples used the `ubuntu-bionic-systemd-docker`, but you can use any
container image you want. **Sysbox places no requirements on the container image.**

Nestybox has several images which you can find in the [Nestybox Dockerhub registry](https://hub.docker.com/u/nestybox).
Those same images are in the [Nestybox GitHub registry](https://github.com/orgs/nestybox/packages).

We usually rely on `registry.nestybox.com` as an image front-end so that Docker
image pulls are forwarded to the most suitable repository without impacting our
users.

## Mounting Storage into Sysbox Containers (or Pods)

Refer to the [Storage chapter](storage.md).

## Deploying containers with sysbox-runc directly

**NOTE: This is not the usual way to deploy containers with Sysbox as the
interface is low-level (it's defined by the OCI runtime spec). However, we
include it here for reference because it's useful when wishing to control the
configuration of the system container at the lowest level.**

As the root user, follow these steps:

1.  Create a rootfs image for the system container:

```console
# mkdir /root/syscontainer
# cd /root/syscontainer
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
        container's rootfs should be owned by `root:root`.

    -   If the `config.json` does specify the Linux user namespace and associated
        user-ID and group-ID mappings, the container's rootfs should be owned
        by the corresponding user-ID and group-ID.

    -   In addition, make sure you have support for either [shiftfs](design.md#ubuntu-shiftfs-module)
        or ID-mapped mounts (kernel >= 5.12) in your host. Without these,
        host files mounted into the container will show up with `nobody:nogroup`
        ownership.

-   Feel free to modify the system container's `config.json` to your needs. But
    note that Sysbox ignores a few of the OCI directives in this file (refer to
    the [Sysbox design document](design.md#sysbox-oci-compatibility) for details).

## Using Other Container Managers

We currently only support the above methods to run containers with
Sysbox. However, other OCI-based container managers will most likely work.
