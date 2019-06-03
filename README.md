Nestybox Sysvisor
=================

## Introduction

Sysvisor is a container runtime that enables creation of system
containers.

A system container is a container whose main purpose is to package and
deploy a full operating system environment; see
[here](https://github.com/nestybox/nestybox#system-containers) for
more info.

Sysvisor system containers use all Linux namespaces (including the
user-namespace) and cgroups for strong isolation from the underlying
host and other containers.


## Key Features

* Designed to integrate with Docker

  - Users launch and manage system containers with Docker (i.e.,
    `docker run ...`), just as with any other container.

  - Leverages Docker's container image caching & sharing technology
    (storage efficient).

* Strong container-to-host isolation via use of *all* Linux namespaces

  - Including the user namespace (i.e., root in the system container
    maps to a non-root `nobody:nogroup` user in the host).

* Supports Docker daemon configured with `userns-remap` or without it.

  - With `userns-remap`, Docker manages the container's user
    namespace; however, Docker currently assigns all containers the
    same user-id/group-id mapping, reducing container-to-container
    isolation.

  - Without userns-remap, Sysvisor manages the container's user
    namespace; Sysvisor assigns *exclusive* user-id/group-id mappings
    to each container, for improved container-to-container isolation.

* Supports running Docker *inside* the system container.

  - Securely, without using Docker privileged containers.

* Supports shared storage between system containers

  - Without requiring lax permissions on the shared storage.

The following sections describe how to use each of these features.


## Sysvisor Components

Sysvisor is made up of the following components:

* sysvisor-runc

* sysvisor-fs

* sysvisor-mgr


sysvisor-runc is the program that creates containers. It's the
frontend of sysvisor: higher layers (e.g., Docker) invoke
sysvisor-runc to launch system containers.

sysvisor-fs is a file-system-in-user-space (FUSE) that emulates
portions of the container's filesystem, in particular the `/proc/sys`
directory. It's purpose is to expose system resources inside the
system container with proper isolation from the host.

sysvisor-mgr is a daemon that provides services to sysvisor-runc and
sysvisor-fs. For example, it manages assignment of exclusive user
namespace subuid mappings to system containers.

Together, sysvisor-fs and sysvisor-mgr are the backends for
sysvisor. Communication between sysvisor components is done via gRPC.


## Supported Linux Distros

* Ubuntu 18.10 (codename Cosmic)


## Host Requirements

* Docker must be installed on the host machine.

* The host's kernel should be configured to allow unprivileged users
  to create namespaces. This config likely varies by distro.

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

Launch Sysvisor with:

```
$ sudo sysvisor &
```

This launches the sysvisor-fs and sysvisor-mgr daemons. The daemons
will log into `/var/log/sysvisor-fs.log` and
`/var/log/sysvisor-mgr.log` (these logs are useful for
troubleshooting).


## Usage

The easiest way to create system containers is to use Docker in
conjunction with Sysvisor. It's also possible to use Sysvisor directly
(without Docker), but it's a lower level interface and thus a bit more
cumbersome to use.

### Docker + Sysvisor

Start by configuring the Docker daemon by creating or editing the
`/etc/docker/daemon.json` file:

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

Create a 'sysvisor' user that matches the one configured above in
"userns-remap" section.

```
$ sudo useradd sysvisor
```

Then re-start the Docker daemon. In hosts with systemd:

```
$ sudo systemctl restart docker.service
```

Finally, launch system containers with Docker:

```
$ docker run --runtime=sysvisor-runc \
    --rm -it --hostname syscont \
    debian:latest
root@syscont:/#
```

Inside the system container, you can install and launch system
software such as another Docker daemon to spawn app containers. See
section System Container below for further info on this.


### Docker + Sysvisor (without userns-remap)

In the prior section, the Docker daemon was configured with the
`userns-remap` option. This causes Docker to enable the user namespace
for containers and manage the associated user-id (uid) and group-id
(gid) mappings.

Docker `userns-remap` offers strong container-to-host isolation by
virtue of mapping root in the container to a non-root user in the
host.

However, Docker userns-remap offers weak container-to-container
isolation. The reason is that Docker uses the same uid(gid) mapping
for all containers. That is, all containers will map to the *same*
non-root uid(gids) on the host. A process that escapes the container
would have permission to access the data of other containers.

To improve on this, Sysvisor supports running system containers
*without* Docker `userns-remap`. In this mode, Sysvisor (rather than
Docker) manages the user-namespace uid(gid) mappings on the host. This
results in strong container-to-host and container-to-container
isolation. A process that escapes the container would have no
permission to access the data of other containers.

To work without `userns-remap`, Sysvisor requires that a filesystem
overlay module called `shiftfs` be loaded in the kernel. See section
"Shiftfs Module" below for details on how to do this.

Once shiftfs is loaded in the kernel, simply configure the
`/etc/Docker/daemon.json` file without `userns-remap`:

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
$ docker run --runtime=sysvisor-runc \
    --rm -it --hostname syscont \
    debian:latest
root@syscont:/#
```

### Sysvisor (without Docker)

**TODO**: write this section


## System Container

### Supported apps

* Docker

  - May be installed inside a system container using the instructions
    in the Docker website.

  - Alternatively, use a system container image that containers a
    pre-installed Dockerd (e.g.,
    `nestybox/sys-container:debian-plus-Docker`)


## Shared Volumes

System containers use the Linux user-namespace for increased isolation
from the host and from other containers (i.e., each container has a
range of uids(gids) that map to a non-root user in the host).

A known issue with containers that use the user-namespace is that
sharing storage between them is not trivial because each container can
be potentially given an exclusive uid(gid) range on the host, and thus
may not have access to the shared storage (unless such storage has lax
permissions).

Sysvisor system containers support storage sharing between multiple
system containers, without lax permissions and in spite of the fact
that each system container may be assigned a different uid/gid range
on the host.

This uses uid(gid) shifting performed by the `shiftfs` module describe
previously (see section "Docker without userns-remap" above).

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

shiftfs is a Linux kernel module that provides a thin overlay
filesystem that performs uid and gid shifting betweeen user
namespaces.

shiftfs was originally written by James Bottomley and has been
modified slightly by Nestybox (bug fixes, adaptation to supported
Sysvisor distros, etc.). See [here](https://github.com/nestybox/sysvisor/blob/master/shiftfs/README.md)
for details on shiftfs.

### Installation

Build and load the `shiftfs` module with:

```
cd shiftfs/<distro>/
sudo make
sudo insmod shiftfs.ko
```

Remove the module with:

```
sudo rmmod shiftfs
```

## Sysvisor Testing

The Sysvisor test suite is made up of the following:

* sysvisor-mgr unit tests
* sysvisor-fs unit tests
* sysvisor-runc unit and integration tests
* sysvisor integration tests (these test sysvisor runc, mgr, and fs together).

### Running the entire suite

To run the entire Sysvisor test suite:

```
$ make test
```

This command runs all test targets (i.e., unit and integration
tests).

*Note*: This includes sysvisor integration tests with and without
uid-shifting. Thus the shiftfs module be loaded in the kernel *prior*
to running this command. See above for info on loading shiftfs.

### Running the sysvisor integration tests only

Without uid-shifting:

```
$ make test-sysvisor
```

With uid-shifting:

```
$ make test-sysvisor-shiftuid
```

It's also possible to run a specific integration test with:

```
$ TESTPATH=/<test-name> make test-sysvisor
```

where `<test-name>` is one of the `*.bats` files in the Sysvisor `tests/` directory.

### Running the unit tests

To run unit tests for one of the Sysvisor components (e.g., sysvisor-fs, sysvisor-mgr, etc.)

```
$ make test-runc
$ make test-fs
$ make test-mgr
```

These unit tests run inside a privileged container, as some of them
require running as root. There are also "local" targets for the `mgr`
and `fs` unit tests which run directly on the host (e.g., `make
test-fs-local`, `make test-mgr-local`). These local targets run faster,
but will skip tests that require root permissions.

### More on Sysvisor integration tests

The Sysvisor integration Makefile target (`test-sysvisor`) spawns a
Docker privileged container using the image in tests/Dockerfile.

It then mounts the developer's Sysvisor directory into the privileged
container, builds and installs Sysvisor *inside* of it, and runs the
tests in directory `tests/`.

These tests use the ["bats"](https://github.com/nestybox/sysvisor/blob/master/README.md)
test framework, which is pre-installed in the privileged container
image.

In order to launch the privileged container, Docker must be present in
the host and configured without userns-remap (as userns-remap is not
compatible with privileged containers). Make sure the
`/etc/docker/daemon.json` file is not configured with the
`userns-remap` option prior to running the Sysvisor integration tests.

Also, in order to debug, it's sometimes useful to launch the Docker
privileged container and get a shell in it. This can be done with:

```
$ make test-shell
```

or

```
$ make test-shell-shiftuid
```

The latter command configures docker inside the privileged test
container without userns remap, thus forcing sysvisor to use
uid-shifting.

### Testing Shiftfs

We use the [pjdfstest suite](https://github.com/pjd/pjdfstest) to test
shiftfs POSIX compliance.

To run the tests, use:

```
make test-shiftfs
```

This target launches the privileged test container, creates a test
directory, mounts shiftfs on this directory, and runs the pjdfstest
suite.

Make sure to run the test target only on Linux distros in which
shiftfs is supported.

### Test cleanup

The test suite creates directories on the host which it mounts into
the privileged test container. The programs running inside the
privileged container (e.g., docker, sysvisor, etc) place data in these
directories.

The sysvisor test targets do not cleanup the contents of these
directories so as to allow their reuse between test runs in order to
speed up testing (e.g., to avoid having the test container download
fresh docker images between subsequent test runs).

Instead, cleanup of these directories must be done manually via the
following make target:

```
$ sudo make test-cleanup
```

The target must be run as root, because some of the files being
cleaned up were created by root processes inside the privileged test
container.

## Troubleshooting

Refer to the Sysvisor [troubleshooting notes](https://github.com/nestybox/sysvisor/blob/master/docs/troubleshoot.md).

## Debugging

Refer to the Sysvisor [debugging notes](https://github.com/nestybox/sysvisor/blob/master/docs/debug.md)
for detailed information on the sequence of steps required to debug
Sysvisor modules.
