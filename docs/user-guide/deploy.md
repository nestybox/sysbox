# Sysbox User Guide: Container Deployment

## Contents

-   [Deploying System Containers](#deploying-system-containers)

## Deploying System Containers

We currently support two ways of deploying system containers with Sysbox:

1) Using Docker (the easy and preferred way)

2) Using the `sysbox-runc` command directly (more control but harder)

Both of these are explained below.

Note that higher level tools that use Docker to deploy containers will
most likely work with Sysbox without problem.

### Using Docker

Simply add the `--runtime=sysbox-runc` flag in the `docker run` command:

```console
$ docker run --runtime=sysbox-runc --rm -it --hostname my_cont debian:latest
root@my_cont:/#
```

The resulting container is one in which you can seamlessly run run systemd,
Docker, and Kubernetes inside (without complex images, entrypoints, etc). See
the [Quickstart Guide](../quickstart/README.md) for examples.

If you wish, you can configure Sysbox as the default runtime for Docker. This
way you don't have to use the `--runtime` flag every time. To do this,
refer to this [Docker doc](https://docs.docker.com/engine/reference/commandline/dockerd/).

Almost all Docker functionality works with Sysbox, but there are a few
exceptions. See the [Sysbox limitations doc](limitations.md) for further info.

### Using the sysbox-runc command directly

This is useful when wishing to control the configuration of the system container
at the lowest level.

As the root user, follow these steps:

1) Create a rootfs image for the system container:

```console
# mkdir /root/syscontainer
# cd /root/syscontainer
# mkdir rootfs
# docker export $(docker create debian:latest) | tar -C rootfs -xvf -
```

2) Create the OCI spec (i.e., `config.json` file) for the system container:

```console
# sysbox-runc spec
```

3) Launch the system container.

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

### Using Other Container Managers

We officially only support the above methods to run Sysbox.

However, we plan to add support for other OCI-compatible [container managers](concepts.md#container-manager) soon
(e.g., [cri-o](https://cri-o.io/)).
