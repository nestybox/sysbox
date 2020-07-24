# Sysbox Internal User Guide: Design Notes

The customer docs for sysbox contain basic info on its design.
See [here](https://github.com/nestybox/sysbox-staging/blob/master/docs/design.md).

The following is additional design information meant for Nestybox's
internal use only.

## OCI compatibility

See [here](https://github.com/nestybox/sysbox-staging/blob/master/docs/design.md#oci-compatibility)
for info on Sysbox's OCI compatibility.

Additional info below.

### Init Process

-   Sysbox honors the init process selected for the system container
    via the spec's `Process` object.

-   Normally, we expect that the init process in a system container will
    be an init daemon (e.g., systemd). But that's not always true, and
    Sysbox will execute whatever entry point is specified in the spec.

### Capabilities

-   If the `Process` object indicates a uid of 0, sysbox gives that
    process full capabilities regardless of what the system container's
    spec indicates.

        CapInh: 0000003fffffffff
        CapPrm: 0000003fffffffff
        CapEff: 0000003fffffffff
        CapBnd: 0000003fffffffff
        CapAmb: 0000003fffffffff

-   If the `Process` object indicates a uid != 0, sysbox gives that
    process the following capabilities:

        CapInh: 0000000000000000
        CapPrm: 0000000000000000
        CapEff: 0000000000000000
        CapBnd: 0000003fffffffff
        CapAmb: 0000000000000000

-   The above applies to processes that enter the system container via
    any of the defined entry points (i.e., `sysbox-runc run` or
    `sysbox-runc exec`).

-   Processes created inside the system container (i.e., children of the
    sys container's init process) get capabilities per Linux rules (see
    capabilities(7)).

-   The above behavior reflects that of a real Linux host.

-   Note that unlike the OCI runc, sysbox does not honor the
    capabilities in the OCI spec. For example, it's not possible to set
    the capabilities of the sys container's processes via the
    `docker run --cap-add` or `--cap-drop` options.

### Cgroups

-   The system container's cgroupfs is mounted read-write in order to
    allow a root process in the system container to create cgroups.

    -   This functionality is needed to run system software such as Docker
        or Systemd inside the system container.

-   However, it's critical to prevent a root process in the system
    container from changing the cgroup resources assigned to the system
    container itself. To do this, Sysbox creates two cgroup
    directories for each system container on the host:

    `/sys/fs/cgroup/<controller>/<syscont-id>/`
    `/sys/fs/cgroup/<controller>/<syscont-id>/syscont-cgroup-root/`

-   The first directory is not exposed inside the container; it's
    configured with the host resources assigned to the system container.
    The system container has no visibility and permissions to access it.

-   The second directory is exposed inside the system container.
    Sysbox gives the root user in the system container full access to
    it (i.e., mounts it read-write as the system container's cgroup root, and
    changes the ownership on the host to match the system container's
    root process uid(gid)).

-   In addition, Sysbox uses the cgroup namespace to hide the host
    path for the cgroup root inside the system container.

### Read-only paths

-   Sysbox will honor read-only paths in the system container
    spec, except when these correspond to paths managed by
    sysbox-fs.

    -   The rationale is that sysbox-fs paths are required for system
        container operation; thus sysbox-fs decides how to expose the
        path.

    -   This may change in the future as use cases arise.

### Masked paths

-   Sysbox will honor masked paths in the system container
    spec, except when these correspond to paths managed by
    sysbox-fs.

    -   The rationale is that sysbox-fs paths are required for system
        container operation; thus sysbox-fs decides how to expose the
        path.

    -   This may change in the future as use cases arise.

## Procfs Virtualization

Sysbox performs partial virtualization of the system container's
procfs (i.e., `/proc`).

The main goals for this are:

1) Make the container feel more like a real host. This in turn
   increases the types of programs that can run inside the container.

2) Increase isolation between the container and the host.

Currently, Sysbox does virtualization of the following procfs resources:

-   `/proc/uptime`

    -   Shows the uptime of the system container, not the host.

-   `/proc/sys/net/netfilter/nf_conntrack_max`

    -   Sysbox emulates this resource independently per system
        container, and sets appropriate values in the host kernel's
        `nf_conntrack_max`.

Note also that by virtue of enabling the Linux user namespace in all
system containers, kernel resources under `/proc/sys` that are not
namespaced by Linux (e.g., `/proc/sys/kernel/*`) can't be changed from
within the system container. This prevents programs running inside the
system container from writing to these procfs files and affecting
system-wide settings.

## uid(gid) mappings

-   If the container spec specifies uid(gid) mapping, sysbox honors it

    -   sysbox does not allocate the mapping in this case

    -   sysbox requires that the mapping be for a range of >= 64K uid(gid)s per container.

        -   This is necessary to support running most Linux distros inside a
            system container (e.g., Debian uses uid 65534 as "nobody").

    -   sysbox does not require that the mappings between containers be non-overlapping
        in this case; sysbox honors the given map, regardless of whether it overlaps
        with other containers.

        -   It's up to the higher layer to provide non-overlapping uid
            mappings between containers for strong container->container
            isolation.

-   Otherwise, sysbox allocates the uid(gid) mapping

    -   the mapping is allocated from the subuid/subgid range for user "sysbox"

    -   each sys container is given an exclusive portion of the subuid(gid) range (for strong isolation)

    -   if the subuid(gid) range is exhausted, action is determined by subuid(gid)
        range exhaust policy setting.

    -   sysbox allocations are always for 64K uid(gid)s

### subuid(gid) range exhaust policy

This policy dictates how sysbox reacts to subuid(gid) range
exhaustion when uid(gid) auto allocation is enabled.

-   Re-use: re-use uid(gid) mappings; this may cause multiple sys
    containers to map to the same subuid(gid) range on the host, reducing
    isolation.

-   No-Reuse: do not launch sys container.

This policy can be configured via sysbox-mgr's `subid-policy`
command line option.

## uid(gid) shifting

Sysbox-runc uses the Ubuntu shiftfs module to help setup system
containers when the Docker daemon is configured without userns-remap
(as it is by default).

In this case the system container rootfs files are owned by true
root and are normally located under `/var/lib/docker/...`.

When a user launches the system container with Docker, sysbox-runc
detects that the container does not have a uid(gid) mapping and
generates one. It then creates the container and mounts shiftfs on the
system container's rootfs. This allows the system container's root
user to access the container's rootfs without problem.

Here is an example of a system container's mounts without Docker
userns-remap (i.e., with uid(gid) shifting):

    TARGET                                SOURCE                                                                     FSTYPE   OPTIONS
    /                                     /mnt/extra1/var/lib/docker/btrfs/subvolumes/85de4382d74241e0c4aed28bac79229311c456b7d817777e5a04d0637d35800b
    |                                                                                                                shiftfs  rw,relatime,userns=/proc/15517/ns/user
    |-/proc                               proc                                                                       proc     rw,nosuid,nodev,noexec,relatime
    | |-/proc/bus                         proc[/bus]                                                                 proc     ro,relatime

Notice how shiftfs is mounted on the container's rootfs.

uid(gid) shifting is not used by sysbox when Docker userns-remap is
enabled, as in this case Docker ensures that the container's rootfs is
owned by the same host user that maps to the container's root
user. Sysbox-runc detects this situation and does not use shiftfs on
the container rootfs.

Here is an example of a system container mounts with Docker userns-remap
(i.e., without uid(gid) shifting):

    $ docker run -it --rm --runtime=sysbox-runc debian:latest
    root@92ce5789c394:/# findmnt
    TARGET                                SOURCE                                      FSTYPE   OPTIONS
    /                                     /dev/sda[/var/lib/docker/231072.231072/btrfs/subvolumes/70d8a082b1d2f0fab5b918aa634d7448fd19292db1b3ae721be68172022b9522]
    |                                                                                 btrfs    rw,relatime,space_cache,user_subvol_rm_allowed,subvolid=3355,subvol=/var/lib/docker/231072.231072/btrfs/subvolumes/70d8a082b1d2f0fab5b918aa634d7448fd19292db1b3ae721be68172022b9522
    |-/proc                               proc                                        proc     rw,nosuid,nodev,noexec,relatime
    | |-/proc/bus                         proc[/bus]                                  proc     ro,relatime
    | |-/proc/fs                          proc[/fs]                                   proc     ro,relatime
    | |-/proc/irq                         proc[/irq]                                  proc     ro,relatime

Notice how shiftfs is not mounted in the container's rootfs (there was
no need to).

## Shiftfs on Bind Mount Sources

In addition to mounting shiftfs on the container's rootfs,
sysbox-runc also mounts shiftfs on the source directory of bind
mounts specified in the container's runc spec, if they meet
the following conditions:

-   The bind mount source is not under of the container's rootfs (to
    avoid shiftfs-on-shiftfs mounts).

-   The bind mount source is not directly above the container's rootfs
    (to avoid shiftfs-on-shifts mounts).

-   The bind mount source uid:gid do not match the uid:gid assigned
    to the container's root process.

This way, sysbox-runc supports uid(gid) shifting on Docker
volume or bind mounts.

For example, the following command causes sysbox-runc to mount shiftfs
on directory `/tmp/my-vol`.

    $ docker run --runtime sysbox-runc --mount type=bind,source=/tmp/my-vol,target=/mnt/shared ...

This also allows sysbox-runc to support sharing of volumes across
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

## Sysbox and Docker userns-remap

Based on the above, the following is sysbox's behavior with respect
to Docker userns remap:

| Docker userns-remap | Description                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| disabled            | sysbox will allocate exclusive uid(gid) mappings per sys container and perform uid(gid) shifting. |
|                     | Strong container-to-host isolation.                                                               |
|                     | Strong container-to-container isolation.                                                          |
|                     | Storage efficient (shared Docker images).                                                         |
|                     | Requires the shiftfs module in kernel.                                                            |
|                     |                                                                                                   |
| enabled             | sysbox will honor Docker's uid(gid) mappings.                                                     |
|                     | uid(gid) shifting won't be used because container uid(gid) mappings match rootfs owner.           |
|                     | Strong container-to-host isolation.                                                               |
|                     | Reduced container-to-container isolation (same uid(gid) range).                                   |
|                     | Storage efficient (shared Docker images).                                                         |
|                     | Does not require the shiftfs module in kernel.                                                    |

## System container /var/lib/docker mount

Sysbox automatically creates and bind-mounts a host volume inside the
system container's `/var/lib/docker` directory.

This functionality is needed in order to:

-   Remove the need to place sysbox system container images in a
    filesystem that supports Docker-in-Docker (e.g., btrfs).

-   Allow Docker-in-Docker when the outer Docker system container is
    using uid-shifting (via the shiftfs module). This is needed because
    the inner Docker mounts overlayfs on top of the container images on
    `/var/lib/docker/`, but overlayfs does not work when mounted on top
    of shiftfs, so shiftfs can't be mounted on `/var/lib/docker`.

See sysbox github issue #46 (<https://github.com/nestybox/sysbox/issues/46>) for
further details.

The host volume that is bind mounted on the system container's
`/var/lib/docker` is simply a directory inside sysbox-mgr's
data-root (`/var/lib/sysbox`). This directory is created by sysbox
when the container launches, and deleted when the container stops. In
other words, the volume / directory only exists for the life of the
system container.

This ensures that each instance of a container image gets a dedicated
`/var/lib/docker` directory and thus each Docker daemon inside the
system container(s) has an exclusive docker-storage area (as sharing
of a docker-storage area among Docker daemons does not work per
Docker).

A couple of details:

-   When creating the host volume directory, Sysbox sets the directory's
    uid:gid ownership to match the uid:gid of the root inside the system
    container. This way system container root processes can access
    `/var/lib/docker` inside the system container.

-   Sysbox deals with the case where the system container image has
    contents in `/var/lib/docker` prior to launching the system
    container.  In this case, sysbox copies those contents to the
    newly created volume and sets the uid:gid ownership appropriately
    before performing the bind mount of the volume on top of the
    container's `/var/lib/docker/`.

### Implementation

The creation and deletion of the host volume to be mounted on `/var/lib/docker`
is done by sysbox-mgr.

When a system container starts, sysbox-runc requests a supplementary
mount config from sysbox-mgr. sysbox-mgr then creates the host
volume in its data-root (`/var/lib/sysbox`) and returns a mount
config to sysbox-runc. sysbox-runc then applies the mount config
(i.e., bind mounts the host volume to the container's `/var/lib/docker`).

When a system container stops, sysbox-runc requests that sysbox-mgr
release any resources associated with the container. sysbox-mgr proceeds
to remove the host volume associated with the container.

## System Container /var/lib/kubelet mount

Sysbox automatically creates and bind-mounts a host volume inside the
system container's `/var/lib/kubelet` directory.

This functionality is needed in order to prevent problems with the K8s
kubelet, which does not recognize `shiftfs` as a supported
file-system.

The approach taken for `/var/lib/kubelet` mounts is the exact same
as for `/var/lib/docker` mounts described in the prior section.

## Rootless mode

Sysbox will initially not support running rootless (i.e.,
without root permissions on the host).

In the future we should consider adding this to allow regular
users on a host to launch system containers.

## System Container Syscall Trapping & Emulation

Sysbox supports trapping and emulating some syscalls inside
a system container.

This is done only on control-path syscalls (not data-path to avoid
the performance hit) and it's done in order to provide processes inside
the sys container with a complete abstraction of a "virtual host".

For example, inside a sys container we trap the `mount` system call in
order to ensure that such mounts always result in the sysbox-fs emulated
procfs being mounted, rather than the kernel's procfs. This provides
consistency for the procfs mounts inside the sys container.

To do this trapping and emulation, we use the Linux kernel's seccomp
BPF filters with the "notification action". Sysbox-runc sets up the
notification action on the syscalls that must be trapped, and
sysbox-fs monitors for seccomp notificaitions from the kernel and
performs the emulation of trapped syscalls.

Much more info on seccomp BPF for syscall trapping can be found
[here](https://github.com/nestybox/sysbox/blob/master/knowledge-base/syscall-trapping/syscall_seccomp_bpf.md)
and [in this excellent post by Christian Brauner from LXD](https://people.kernel.org/brauner/the-seccomp-notifier-new-frontiers-in-unprivileged-container-development).
