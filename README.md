Nestybox Sysvisor
=================

## Introduction

Sysvisor is a container runtime that enables creation of system containers.


## Components

Sysvisor is made up of the following components:

* sysvisor-runc

* sysvisor-fs

* sysvisor-mgr


## Building & Installing

First, sysvisor requires that user "sysvisor" be created in the system:

```
$ sudo useradd sysvisor
```

Then build and install with:

```
$ make
$ sudo make install
```

Launch the sysvisor-fs and sysvisor-mgr daemons with:

```
$ sudo sysvisor &
```

The daemons will log into `/var/log/sysvisor-fs.log` and `/var/log/sysvisor-mgr.log` (these logs are useful for troubleshooting).


## Usage

The easiest way to create system containers is to use Docker in conjunction with sysvisor. It's also possible to use sysvisor directly (without Docker), but it's a lower level interface and thus a bit more cumbersome to use.

### Docker + Sysvisor

First, configure the Docker daemon by creating or editing the `/etc/docker/daemon.json` file:

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

Then re-start the Docker daemon; for example:

```
$ sudo systemctl restart docker.service
```

Finally, launch system containers with Docker:

```
$ docker run --runtime=sysvisor-runc --rm -it --hostname syscont debian:latest
root@syscont:/#
```

Inside the system container, you can install and launch system software such as another Docker daemon to spawn app containers. See section System Container below for further info on this.


### Docker without userns-remap

In the prior section, the docker daemon was configured with the `userns-remap` option. This causes Docker to manage user namespace of the container as well as its user-id (uid) and group-id (gid) mappings.

Unfortunately, Docker uses the same uid(gid) mapping for all containers. That is, with docker `userns-remap`, all system containers will map to the same non-root uid(gids) on the host.

Thus, Docker `userns-remap` offers strong container-to-host isolation (compared to Docker without userns-remap), but weak container-to-container isolation.

To improve on this, Sysvisor supports running system containers *without* Docker `userns-remap`. This causes Sysvisor (not Docker) to manage the user-namespace as well as uid(gid) mappings on the host. This results in strong container-to-host and container-to-container isolation.

However, doing so requires that a filesystem overlay module called `shiftfs` be loaded in the kernel.

Build and load the `shiftfs` module with:

```
cd shiftfs/<distro>/
sudo make
sudo insmod shiftfs.ko
```

Configure the `/etc/docker/daemon.json` file without `userns-remap`:

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
$ sudo systemctl restart docker.service
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

  - Alternatively, use a system container image that containers a pre-installed dockerd (e.g., `nestybox/sys-container:debian-plus-docker`)


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


## Troubleshooting

**TODO**: write this section
