Nestybox Sysvisor
=================

## Introduction

Sysvisor is a container runtime that enables creation of system containers.

A system container is a container whose main purpose is to package and deploy a full operating system environment; see [here](https://github.com/nestybox/nestybox#system-containers) for more info.

Sysvisor system containers use all Linux namespaces (including the user-namespace) and cgroups for strong isolation from the underlying host and other containers.


## Key Features

* Designed to integrate with Docker

  - Users launch and manage system containers with Docker (i.e., `docker run ...`), just as with any other container.

  - Leverages Docker's container image caching & sharing technology (storage efficient).

* Strong container-to-host isolation via use of **all** Linux namespaces

  - Including the user namespace (i.e., root in the system container maps to a non-root "nobody:nogroup" user in the host).

* Supports Docker daemon configured with "userns-remap" or without it.

  - With userns-remap, Docker manages the container's user namespace; however, Docker currently assigns all containers the same user-id/group-id mapping, reducing container-to-container isolation.

  - Without userns-remap, Sysvisor manages the container's user namespace; sysvisor assigns **exclusive** user-id/group-id mappings to each container, for improved container-to-container isolation.

* Supports running Docker **inside** the system container.

  - Securely, without using Docker privileged containers.

* Supports shared storage between system containers

  - Without requiring lax permissions on the shared storage.

The following sections describe how to use each of these features.


## Sysvisor Components

Sysvisor is made up of the following components:

* sysvisor-runc

* sysvisor-fs

* sysvisor-mgr


sysvisor-runc is the program that creates containers; it's a fork of the [OCI runc](https://github.com/opencontainers/runc), but has been modified to run system containers. It's mostly but not totally OCI compatible. Docker interacts with sysvisor-runc.

sysvisor-fs is a file-system-in-user-space (FUSE) that emulates portions of the container's filesystem, in particular the "/proc/sys" directory. It's purpose is to expose system resources inside the system container with proper isolation from the host.

sysvisor-mgr is a daemon that provides services to sysvisor-runc and sysvisor-fs. For example, it manages assignment of exclusive user namespace subuid mappings to system containers.


## Supported Linux Distros

* Ubuntu 18.10 (codename Cosmic)


## Host Requirements

* Docker must be installed on the host machine.

* The host's kernel should be configured to allow unprivileged users to create namespaces. This config likely varies by distro.

  Ubuntu:

  ```
  sudo sh -c "echo 1 > /proc/sys/kernel/unprivileged_userns_clone"
  ```

* User "sysvisor" must be created in the system:

```
$ sudo useradd sysvisor
```

## Building & Installing

```
$ make
$ sudo make install
```

Launch sysvisor with:

```
$ sudo sysvisor &
```

This launches the sysvisor-fs and sysvisor-mgr daemons. The daemons will log into `/var/log/sysvisor-fs.log` and `/var/log/sysvisor-mgr.log` (these logs are useful for troubleshooting).


## Usage

The easiest way to create system containers is to use Docker in conjunction with sysvisor. It's also possible to use sysvisor directly (without Docker), but it's a lower level interface and thus a bit more cumbersome to use.

### Docker + Sysvisor

Start by onfiguring the Docker daemon by creating or editing the `/etc/Docker/daemon.json` file:

```
{
   "userns-remap": "sysvisor",
   "runtimes": {
        "sysvisor-runc": {
            "path": "/usr/local/sbin/sysvisor-runc"
        }
    }
}
```

Then re-start the Docker daemon. In hosts with systemd:

```
$ sudo systemctl restart Docker.service
```

Finally, launch system containers with Docker:

```
$ docker run --runtime=sysvisor-runc --rm -it --hostname syscont debian:latest
root@syscont:/#
```

Inside the system container, you can install and launch system software such as another Docker daemon to spawn app containers. See section System Container below for further info on this.


### Docker + Sysvisor (without userns-remap)

In the prior section, the Docker daemon was configured with the `userns-remap` option. This causes Docker to enable the user namespace for containers and manage the associated user-id (uid) and group-id (gid) mappings.

Docker `userns-remap` offers strong container-to-host isolation by virtue of mapping root in the container to a non-root user in the host.

However, Docker userns-remap offers weak container-to-container isolation. The reason is that Docker uses the same uid(gid) mapping for all containers. That is, all containers will map to the **same** non-root uid(gids) on the host. A process that escapes the container would have permission to access the data of other containers.

To improve on this, Sysvisor supports running system containers *without* Docker `userns-remap`. In this mode, Sysvisor (rather than Docker) manages the user-namespace uid(gid) mappings on the host. This results in strong container-to-host and container-to-container isolation. A process that escapes the container would have no permission to access the data of other containers.

To work without `userns-remap`, Sysvisor requires that a filesystem overlay module called `shiftfs` be loaded in the kernel. See section "Shiftfs Module" below for details on how to do this.

Once shiftfs is loaded in the kernel, simply configure the `/etc/Docker/daemon.json` file without `userns-remap`:

```
{
   "runtimes": {
        "sysvisor-runc": {
            "path": "/usr/local/sbin/sysvisor-runc"
        }
    }
}
```

Re-start the Docker daemon:

```
$ sudo systemctl restart Docker.service
```

And launch system containers with Docker:

```
$ docker run --runtime=sysvisor-runc --rm -it --hostname syscont debian:latest
root@syscont:/#
```


## System Container

### Supported apps

* Docker

  - May be installed inside a system container using the instructions in the Docker website.

  - Alternatively, use a system container image that containers a pre-installed Dockerd (e.g., `nestybox/sys-container:debian-plus-Docker`)


## Shared Volumes

System containers use the Linux user-namespace for increased isolation from the host and from other containers (i.e., each container has a range of uids(gids) that map to a non-root user in the host).

A known issue with containers that use the user-namespace is that sharing storage between them is not trivial because each container can be potentially given an exclusive uid(gid) range on the host, and thus may not have access to the shared storage (unless such storage has lax permissions).

Sysvisor system containers support storage sharing between multiple system containers, without lax permissions and in spite of the fact that each system container may be assigned a different uid/gid range on the host.

This uses uid(gid) shifting performed by the `shiftfs` module describe previously (see section "Docker without userns-remap" above).

Setting it up is simple:

First, create a shared directory owned by root:

```
sudo mkdir <path/to/shared/dir>
```

Then mark the shared directory with `shiftfs`:

```
$ sudo mount -t shiftfs -o mark <path/to/shared/dir>
```

Then simply bind mount the volume into the system containers:

```
$ docker run --runtime=sysvisor-runc \
    --rm -it --hostname syscont \
    --mount type=bind,source=<path/to/shared/dir>,target=</mount/path/inside/container>  \
    debian:latest
```

After this, all system containers will have root access to the shared volume.


## Shiftfs Module

shiftfs is a Linux kernel module that provides a thin overlay filesystem that performs uid and gid shifting betweeen user namespaces.

shiftfs was originally written by James Bottomley and has been modified slightly by Nestybox (bug fixes, adaptation to supported sysvisor distros, etc.). See [here](https://github.com/nestybox/sysvisor/blob/master/shiftfs/README.md) for details on shiftfs.

### Installation

Build and load the `shiftfs` module with:

```
cd shiftfs/<distro>/
sudo make
sudo insmod shiftfs.ko
```


## Testing

To run the full sysvisor test suite (integration + unit tests):

```
$ sudo make test
```

To run the sysvisor integration tests only:

```
$ sudo make test-sysvisor
```

To run unit tests for one of the sysvisor components (e.g., sysvisor-fs, sysvisor-mgr, etc.)

```
$ make test-runc
$ make test-fs
$ make test-mgr
```

### Sysvisor integration tests

The sysvisor integration Makefile target (`test-sysvisor`) spawns a Docker privileged container, installs sysvisor *inside* of it, and runs the tests in directory `tests/`.

In order to debug, it's sometimes useful to launch the Docker privileged container and get a shell in it. This can be done with:

```
$ make test-shell
```

## Sysvisor-runc OCI Compatibility

**TODO**: write this section


## Troubleshooting

**TODO**: write this section
