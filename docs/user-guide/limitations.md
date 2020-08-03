# Sysbox User Guide: Functional Limitations

This document describes functional restrictions and limitations of Sysbox and
system containers.

## Contents

-   [Docker Restrictions](#docker-restrictions)
-   [System Container Limitations](#system-container-limitations)
-   [Sysbox Functional Limitations](#sysbox-functional-limitations)

## Docker Restrictions

This section describes restrictions when launching containers with Docker +
Sysbox.

### Support for Docker's `--privileged` Option

Sysbox system containers are incompatible with the Docker `--privileged` flag.

The raison d'être for Sysbox is to avoid the use of (very unsecure) privileged
containers yet enable users to run any type of software inside the container.

Using the Docker `--privileged` + Sysbox will fail:

```console
$ docker run --runtime=sysbox-runc --privileged -it alpine
docker: Error response from daemon: OCI runtime create failed: container_linux.go:364: starting container process caused "process_linux.go:533: container init caused \"rootfs_linux.go:67: setting up ptmx caused \\\"remove dev/ptmx: device or resource busy\\\"\"": unknown.
ERRO[0000] error waiting for container: context canceled
```

### Support for Docker's `--userns=host` Option

When Docker is configured in userns-remap mode, Docker offers the ability
to disable that mode on a per container basis via the `--userns=host`
option in the `docker run` and `docker create` commands.

This option **does not work** with Sysbox (i.e., don't use
`docker run  --runtime=sysbox-runc --userns=host ...`).

Note that usage of this option is rare as it can lead to the problems as
described [in this Docker article](https://docs.docker.com/engine/security/userns-remap/#disable-namespace-remapping-for-a-container).

### Support for Docker's `--pid=host` and `--network=host` Options

System containers do not support sharing the pid or network namespaces
with the host (as this is not secure and it's incompatible with the
system container's user namespace).

For example, when using Docker to launch system containers, the
`docker run --pid=host` and `docker run --network=host` options
do not work with system containers.

### Support for Docker's `--read-only` Option

Sysbox does not support system containers configured with a read-only rootfile
system (e.g., those created with the `docker run --read-only` flag):

```console
$ docker run --runtime=sysbox-runc --read-only -it alpine
docker: Error response from daemon: OCI runtime create failed: error in the container spec: invalid or unsupported container spec: root path must be read-write but it's set to read-only: unknown.
```

The rationale is that system containers are designed to run system-level
software, and such software can't run properly on a read-only filesystem.

### Docker cgroup driver restriction

Docker uses the Linux cgroups feature to place resource limits on containers.

Docker supports two cgroup drivers: `cgroupfs` and `systemd`.
In the former, Docker directly manages the container resource
limits. In the latter, Docker works with Systemd to manage the
resource limits. The `cgroupfs` driver is the default driver.

Sysbox currently requires that Docker be configured with the
`cgroupfs` driver. Sysbox does not currently work when Docker is
configured with the `systemd` cgroup driver.

### Support for Exposing Host Devices inside System Containers

Sysbox does not currently support exposing host devices inside system
containers (e.g., via the `docker run --device` option).

## System Container Limitations

This section describes limitations for software running inside a system
container.

### Creating User Namespaces inside a System Container

Nestybox system container do not currently support creating a user-namespace
inside the system container and mounting procfs in it.

That is, executing the following instruction inside a system container
is not supported:

    unshare -U -i -m -n -p -u -f --mount-proc -r bash

The reason this is not yet supported is that Sysbox is not currently
capable of ensuring that the procfs mounted inside the unshared
namespace is the proper one. We expect to fix this soon.

## Sysbox Functional Limitations

### Sysbox must run as root on the host

Sysbox must run with root privileges on the host system. It won't
work if executed without root privileges.

Root privileges are necessary in order for Sysbox to interact with the Linux
kernel in order to create the containers and perform many of the advanced
functions it provides (e.g., procfs virtualization, sysfs virtualization, etc.)

### Checkpoint and Restore Support

Sysbox does not currently support checkpoint and restore of system containers.

### Sysbox Nesting

Sysbox must run at the host level (or within a privileged container if you must).

Sysbox does not work when running inside a system container. This implies that
we don't support running a system container inside a system container at this
time.
