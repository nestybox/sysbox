Sysvisor Design Notes
=====================

The document describes the design of sysvisor, capturing primarily low
level design issues.

Refer to the [sysvisor README file](https://github.com/nestybox/sysvisor/blob/master/README.md) for a general intro into sysvisor.

# Architecture

Sysvisor is comprised on 3 main components:

* sysvisor-runc: fork of the OCI runc, customized for running system containers.

* sysvisor-fs: FUSE-based filesystem, handles emulation of ceratain
  files in the system container's rootfs, in particular those under
  "/proc/sys".

* sysvisor-mgr: a daemon that provides services to sysvisor-runc and
  sysvisor-fs. For example, it manages assignment of exclusive user
  namespace subuid mappings to system containers.

sysvisor-runc is the frontend for sysvisor; higher layers (e.g.,
Docker or Kubernetes via containerd) invoke sysvisor-runc to
launch system containers.

sysvisor-runc is a fork of the [OCI runc](https://github.com/opencontainers/runc),
but has been modified to run system containers. It's mostly but not
totally OCI compatible (see section on System Container Spec
Requirements below for details).

sysvisor-fs and sysvisor-mgr are the backends for sysvisor. Communication
between sysvisor components is done via gRPC.

# System Container Spec Requirements & Overrides

The following are requirements that Sysvisor places on the OCI spec
(i.e., config.json) for a system container.

In cases where the system container spec does not meet these
requirements, depending on the specific config Sysvisor may bail (with
an informative error) or override the config when spawning the
container (with an appropriate log message).

## Init Process

* Sysvisor honors the init process selected for the system container
  via the spec's `Process` object.

* Normally, we expect that the init process in a system container will
  be an init daemon (e.g., systemd). But that's not always true, and
  Sysvisor will execute whatever entry point is specified in the spec.

## Capabilities

* If the `Process` object indicates a uid of 0, sysvisor gives that
  process full capabilities regardless of what the system container's
  spec indicates.

  - This applies to processes that enter the system container via any
    of the defined entry points (i.e., `sysvisor-runc run` or
    `sysvisor-runc exec`).

* If the `Process` object indicates a uid != 0, sysvisor gives that
  process the capabilities defined in the spec; if none are defined,
  it gets no capabilities.

  - This applies to processes that enter the system container via any
    of the defined entry points (i.e., `sysvisor-runc run` or
    `sysvisor-runc exec`).

* Processes created inside the system container (i.e., children of the
  sys container's init process) get capabilities per Linux rules (see
  capabilities(7)).

## Namespaces

* The system container spec must include the following namespaces:

  - user
  - pid
  - ipc
  - uts
  - mount
  - network

* The system container spec may optionally include the
  following namespaces; if not present, Sysvisor will add them.

  - cgroup

* Note: Docker meets these requirements when configured with the
  "userns-remap" option.

## Cgroups

* The system container's cgroupfs is mounted read-write in order to
  allow a root process in the system container to create cgroups.

  - This functionality is needed to run system software such as Docker
    or Systemd inside the system container.

* However, it's critical to prevent a root process in the system
  container from changing the cgroup resources assigned to the system
  container itself. To do this, Sysvisor creates two cgroup
  directories for each system container on the host:

  `/sys/fs/cgroup/<controller>/<syscont-id>/`
  `/sys/fs/cgroup/<controller>/<syscont-id>/syscont-cgroup-root/`

* The first directory is not exposed inside the container; it's
  configured with the host resources assigned to the system container.
  The system container has no visibility and permissions to access it.

* The second directory is exposed inside the system container.
  Sysvisor gives the root user in the system container full access to
  it (i.e., mounts it read-write as the system container's cgroup root, and
  changes the ownership on the host to match the system container's
  root process uid/gid).

* In addition, Sysvisor uses the cgroup namespace to hide the host
  path for the cgroup root inside the system container.

## Read-only paths

* Sysvisor will honor read-only paths in the system container
  spec, except when these correspond to paths managed by
  sysvisor-fs.

  - The rationale is that sysvisor-fs paths are required for system
    container operation; thus sysvisor-fs decides whether to
    how to expose the path.

  - This may change in the future as use cases arise.

## Masked paths

* Sysvisor will honor masked paths in the system container
  spec, except when these correspond to paths managed by
  sysvisor-fs.

  - The rationale is that sysvisor-fs paths are required for system
    container operation; thus sysvisor-fs decides whether to
    how to expose the path.

  - This may change in the future as use cases arise.

## Readonly rootfs

## Pre-start hooks

## Seccomp

## uid/gid mappings

* If the container spec specifies uid/gid mapping, sysvisor honors it

  - sysvisor does not record the mapping in this case

  - sysvisor requires that the mapping be for a range of >= 64K uid/gids per container.

    - This is necessary to support running most Linux distros inside a
      system container (e.g., Debian uses uid 65534 as "nobody").

    - Note: docker userns-remap satisfies this.

  - sysvisor does not require that the mappings between containers be non-overlapping
    in this case; sysvisor honors the given map, regardless of whether it overlaps
    with other containers.

    - It's up to the higher layer to provide non-overlapping uid
      mappings between containers for strong container->container
      isolation.

* Otherwise, sysvisor generates the uid/gid mapping

  - the mapping is generated from the subuid/subgid range for user "sysvisor"

  - each sys container is given an exclusive portion of the subuid/gid range (for strong isolation)

  - if the subuid/gid range is exhausted, action is determined by subuid/gid
    range exhaust policy setting.

  - sysvisor allocations are always for 64K uid/gids

### subuid/gid range exhaust policy

This setting dictates how sysvisor reacts to subuid/gid range
exhaustion when uid/gid auto allocation is enabled.

- Re-use: re-use uid/gid mappings; this may cause multiple sys
  containers to map to the same subuid/gid range on the host, reducing
  isolation.

- No-Reuse: do not launch sys container.

Note: currently the setting is hardwired to "Reuse" in sysvisor-mgr.

# uid(gid) shifting

sysvisor-runc uses the [shiftfs Linux kernel module](https://github.com/nestybox/sysvisor/blob/master/shiftfs/README.md) to support Docker
containers when the Docker daemon is configured without userns-remap
(as it is by default).

In this case the system container rootfs files are owned by true
root and are normally located under `/var/lib/docker/...`.

When a user launches the system container with Docker, sysvisor-runc
detects that the container does not have a uid(gid) mapping and
generates one. It then creates the container and mounts shiftfs on the
system container's rootfs. This allows the system container's root
user to access the container's rootfs without problem.

Here is an example of a system container's mounts without Docker
userns-remap (i.e., with uid(gid) shifting):

```
TARGET                                SOURCE                                                                     FSTYPE   OPTIONS
/                                     /mnt/extra1/var/lib/docker/btrfs/subvolumes/85de4382d74241e0c4aed28bac79229311c456b7d817777e5a04d0637d35800b
|                                                                                                                shiftfs  rw,relatime,userns=/proc/15517/ns/user
|-/proc                               proc                                                                       proc     rw,nosuid,nodev,noexec,relatime
| |-/proc/bus                         proc[/bus]                                                                 proc     ro,relatime
```

Notice how shiftfs is mounted on the container's rootfs.

uid(gid) shifting is not used by sysvisor when Docker userns-remap is
enabled, as in this case Docker ensures that the container's rootfs is
owned by the same host user that maps to the container's root
user. Sysvisor-runc detects this situation and does not use shiftfs on
the container rootfs.

Here is an example of a system container mounts with Docker userns-remap
(i.e., without uid(gid) shifting):

```
$ docker run -it --rm --runtime=sysvisor-runc debian:latest
root@92ce5789c394:/# findmnt
TARGET                                SOURCE                                      FSTYPE   OPTIONS
/                                     /dev/sda[/var/lib/docker/231072.231072/btrfs/subvolumes/70d8a082b1d2f0fab5b918aa634d7448fd19292db1b3ae721be68172022b9522]
|                                                                                 btrfs    rw,relatime,space_cache,user_subvol_rm_allowed,subvolid=3355,subvol=/var/lib/docker/231072.231072/btrfs/subvolumes/70d8a082b1d2f0fab5b918aa634d7448fd19292db1b3ae721be68172022b9522
|-/proc                               proc                                        proc     rw,nosuid,nodev,noexec,relatime
| |-/proc/bus                         proc[/bus]                                  proc     ro,relatime
| |-/proc/fs                          proc[/fs]                                   proc     ro,relatime
| |-/proc/irq                         proc[/irq]                                  proc     ro,relatime
```

Notice how shiftfs is not mounted in the container's rootfs (there was
no need to).

## Shiftfs on Bind Mount Sources

In addition to mounting shiftfs on the container's rootfs,
sysvisor-runc also mounts shiftfs on the source directory of all bind
mounts specified in the container's runc spec (and only when the
source of the bind mount is outside of the container's rootfs).

This way, sysvisor-runc supports uid(gid) shifting on Docker
volume or bind mounts.

For example, the following command causes sysvisor-runc to mount shiftfs
on directory `/tmp/my-vol`.

```
$ docker run --runtime sysvisor-runc --mount type=bind,source=/tmp/my-vol,target=/mnt/shared ...
```

This also allows sysvisor-runc to support sharing of volumes across
system containers.

Without shiftfs, mounting a shared volume across system containers is
challenging. Each system container has a dedicated uid(gid) mapping on
the host. In order to mount a shared volume across multiple system
containers, an administrator would need to configure permissions on
the shared volume such that it can be accessed by the host users
corresponding to the system containers. That requires giving the
shared directory read-write permissions to "other" (which is not safe
as it allows any user on the host to access the directory), or using
access control lists (which is complicated because the container
uid(gid) mappings are generated when the container is spawned).

By using uid(gid) shifting, the shared volume can be owned by true
root (with read-write permissions given to true root only) yet
be shared by multiple system containers.

## Sysvisor and Docker userns-remap

Based on the above, the following is sysvisor's behavior with respect
to Docker userns remap:

| Docker userns-remap | Description |
|---------------------|-------------|
| disabled            | sysvisor will allocate exclusive uid(gid) mappings per sys container and perform uid(gid) shifting. |
|                     | Strong container-to-host isolation. |
|                     | Strong container-to-container isolation. |
|                     | Storage efficient (shared Docker images). |
|                     | Requires shiftfs module in kernel (must be loaded by sysvisor installer). |
|                     |
| enabled             | sysvisor will honor Docker's uid(gid) mappings. |
|                     | uid(gid) shifting won't be used because container uid(gid) mappings match rootfs owner. |
|                     | Strong container-to-host isolation. |
|                     | Reduced container-to-container isolation (same uid(gid) range). |
|                     | Storage efficient (shared Docker images). |
|                     | Does not require shiftfs module in kernel. |


# sysvisor-fs File Emulation


# Rootless mode

Sysvisor will initially not support running rootless (i.e.,
without root permissions on the host).

In the future we should consider adding this to allow regular
users on a host to launch system containers.


# System container security

## Seccomp

## AppArmor

## SELinux
