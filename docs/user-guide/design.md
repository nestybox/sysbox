# Sysbox User Guide: Design Notes

This document briefly describes some aspects of Sysbox's design.

## Contents

-   [Sysbox Components](#sysbox-components)
-   [Ubuntu Shiftfs Module](#ubuntu-shiftfs-module)
-   [Sysbox OCI compatibility](#sysbox-oci-compatibility)

## Sysbox Components

Sysbox is made up of the following components:

-   sysbox-runc

-   sysbox-fs

-   sysbox-mgr

sysbox-runc is a container runtime, the program that does the low
level kernel setup for execution of system containers. It's the
"front-end" of Sysbox: higher layers (e.g., Docker & containerd)
invoke sysbox-runc to launch system containers. It's mostly (but not
100%) compatible with the OCI runtime specification (more on this
[here](design.md#sysbox-oci-compatibility)).

sysbox-fs is a file-system-in-user-space (FUSE) daemon that emulates portions of
the system container's filesystem, in particular portions of procfs and sysfs
mounts inside the system container. It's purpose is to make the system container
closely resemble a virtual host while ensuring proper isolation from the rest of
the system.

sysbox-mgr is a daemon that provides services to sysbox-runc and sysbox-fs. For
example, it manages assignment user-ID and group-ID mappings to system
containers, manages some special mounts that Sysbox adds to system containers,
etc.

Together, sysbox-fs and sysbox-mgr are the "back-ends" for sysbox. Communication
between the sysbox components is done via gRPC.

Users don't normally interact with the Sysbox components directly.  Instead,
they use higher level apps (e.g., Docker) that interact with Sysbox to deploy
system containers.

## Ubuntu Shiftfs Module

When Sysbox [auto assigns user namespace ID mappings](security.md#auto-userns-id-mapping)
it makes use of the `shiftfs` kernel module, which is included in recent Ubuntu kernels
(see the list of [supported Linux distros](../distro-compat.md) for more info on this).

The purpose of this module is to perform filesystem user-ID and
group-ID "shifting" between the container's Linux user namespace and
the host's initial user namespace.

Without the shiftfs module, the system container would see its root filesystem
files owned by `nobody:nogroup`, which in essence renders the container
unusable. The reason is that the container's rootfs is typically owned by
`root:root` on the host, but the container's root user is not root on the
host. Rather it's mapped to a host user-ID selected by Sysbox.

The shiftfs module resolves this problem. By virtue of mounting shiftfs on the
system container's root filesystem (as well as on mount sources), system
container processes will now see files with the correct ownership (i.e.,
directories in the container's `/` directory will have `root:root` ownership
rather than `nobody:nogroup`).

This however also means that files written by the system container's root user
will appear as `root:root` on the host (even though the root user in the system
container is mapped to a fully unprivileged user on the host).

Because of this, some security precautions on the host are needed, as described
in the [next section](#shiftfs-security-precautions).

To verify the Ubuntu shiftfs module is loaded in your host, type:

```console
$ sudo modprobe shiftfs
$ lsmod | grep shiftfs
shiftfs           24576  0
```

The Ubuntu shiftfs module must be present in the kernel when
Sysbox uses [auto userns ID mapping](security.md#auto-userns-id-mapping)
(e.g., when Docker is operating without userns-remap, as it does by default).

The Ubuntu shiftfs module is not used when Sysbox uses [directed userns ID mapping](security.md#directed-userns-id-mapping)
(e.g., when Docker is configured with userns-remap).

Sysbox will check for this. If the module is required but not present
in the Linux kernel, Sysbox will fail to launch containers and issue
an error such as [this one](troubleshoot.md#ubuntu-shiftfs-module-not-present).

### Shiftfs Security Precautions

When Sysbox uses shiftfs, some security precautions are recommended.

These arise from the fact that while the root user in the system container is
mapped to a non-root user on the host, files written by the root user in the
system container to mount-points under shiftfs are mapped into `root:root` on
the host. If the system container is compromised or runs untrusted workloads,
this can cause problems.

For example, an attacker running inside the system container can
create set-user-ID-root executables which can then be executed by
non-root users on the host to gain root privileges.

Note that this vulnerability is not specific to system containers or shiftfs;
the same attack is possible with regular Docker containers because in those the
root user in the container is in fact the root user on the host, so files
written by the root user in the container have `root:root` ownership on the
host.

To reduce the attack surface, the following security precautions are
recommended:

-   The container's root filesystem should be in a directory accessible
    to the host's root user only (e.g., 0700 permissions).

    -   This is always the case when using Docker with Sysbox, because the
        Docker daemon makes `/var/lib/docker` accessible by the host's
        root user only.

-   The container's mount sources on the host should also be in a
    directory only accessible to the host's root user.

    -   This is always the case when using Docker volume and tmpfs mounts,
        since the mount source is also under `/var/lib/docker`.

    -   For bind mounts however this is not guaranteed because the user
        chooses the bind mount source. Thus, the user performing the bind
        mount should explicitly ensure this or take alternative precautions
        as described below.

For cases where the mount source (e.g., a bind mount source) is not in
a directory accessible by the root user only, an alternative
precaution is to mount the bind source as read-only inside the system
container. For example:

```console
$ docker run --runtime=sysbox-runc -it --mount type=bind,source=/path/to/bind/source,target=/path/to/mnt/point,readonly my-syscont
```

If this is not possible (e.g., because the system container must have
write access to the bind mount), another alternative is to explicitly
remount the mount source with the `noexec` attribute on the host prior
to starting the system container:

```console
$ sudo mount --bind /path/to/bind/source /path/to/bind/source
$ sudo mount -o remount,bind,noexec /path/to/bind/source /path/to/bind/source
$ docker run --runtime=sysbox-runc -it --mount type=bind,source=/path/to/bind/source,target=/path/to/mnt/point my-syscont`
```

Note that when a system container starts, Sysbox mounts shiftfs over
the rootfs and mount source. The shiftfs mount implicitly gives them a
`noexec` attribute on the host in order to protect against the attack
described above. However this only lasts while the associated system
container is running.

By explicitly remounting the bind source directory with the `noexec`
attribute as described above, a user can ensure that no user on the
host can execute files within the mount-source directory even after
the container is stopped.

### Shiftfs Functional Limitations

The Ubuntu shiftfs module is very recent and therefore has some
functional limitations as this time.

One such limitation is that overlayfs can't be mounted on top of shiftfs.

This implies that when Sysbox uses shiftfs on a system container, applications
running inside the system container that use overlayfs mounts may not work
properly.

Note that one such application is Docker, which mounts overlayfs over portions
of its `/var/lib/docker` directory. For this specific case however, Sysbox sets
up the system container such that the limitation above is worked-around,
allowing Docker to operate properly within the system container.

A similar work-around is applied by Sysbox to ensure other software such as
Kubernetes and containerd work properly inside the system container.

## Sysbox OCI compatibility

Sysbox is a fork of the [OCI runc](https://github.com/opencontainers/runc). It is mostly
(but not 100%) compatible with the OCI runtime specification.

The incompatibilities arise from our desire to make deployment of system
containers possible with Docker (to save users the trouble of having to learn
yet another tool).

We believe these incompatibilities won't negatively affect users of
Sysbox and should mostly be transparent to them.

Here is a list of OCI runtime incompatibilities:

### Namespaces

Sysbox requires that the system container's `config.json` file have a
namespace array field with at least the following namespaces:

-   pid
-   ipc
-   uts
-   mount
-   network

This is normally the case for Docker containers.

Sysbox adds the following namespaces to all system containers:

-   user
-   cgroup

### Process Capabilities

Sysbox always enables all process capabilities for the system
container's init process when owned by the root user.

Sysbox always disables all process capabilities for the system
container's init process when owned by a non-root user.

See [here](security.md#process-capabilities) for more info.

### Procfs and Sysfs

Sysbox always mounts `/proc` and `/sys` read-write inside the
system container.

Note that by virtue of enabling the Linux user namespace, only
namespaced resources under `/proc` and `/sys` will be writable from
within the system container. Non-namespaced resources (e.g., those
under `/proc/sys/kernel`) won't be writable from within the system
container, unless they are virtualized by Sysbox.

See [Procfs Virtualization](security.md#procfs-virtualization) and
[Sysfs Virtualization](security.md#sysfs-virtualization) for more info.

### Cgroupfs Mount

Sysbox always mounts the cgroupfs as read-write inside the
system container (under `/sys/fs/cgroup`).

This allows programs inside the system container (e.g., Docker) to
assign cgroup resources to child containers. The assigned resources
are always a subset of the cgroup resources assigned to the system
container itself.

Sysbox ensures that programs inside the system container can't
modify the cgroup resources assigned to the container itself, or
cgroup resources associated with the rest of the system.

### Seccomp

Sysbox modifies the system container's seccomp configuration to
whitelist syscalls such as: mount, unmount, pivot_root, and a few
others.

This allows execution of system level programs within the system
container, such as Docker.

### AppArmor

Sysbox currently ignores the Docker AppArmor profile, as it's
too restrictive (e.g., prevents mounts inside the container,
prevents write access to `/proc/sys`, etc.)

See [here](security.md#apparmor) for more on this.

### Read-only and Masked Paths

Sysbox honors read-only paths in the system container's
`config.json`, with the exception of paths at or under `/proc`
or under `/sys`.

The same applies to masked paths.

### Mounts

Sysbox honors the mounts specified in the system container's `config.json`
file, with a few exceptions such as:

-   Mounts over /sys and some of it's sub-directories.

-   Mounts over /proc and some of it's sub-directories.

In addition, Sysbox creates some mounts of its own (i.e., implicitly) within the
system container. For example:

-   Read-only bind mount of the host's `/lib/modules/<kernel-release>`
    into a corresponding path within the system container.

-   Read-only bind mount of the host's kernel header files into
    the corresponding path within the system container.

-   Select mounts under the system container's `/sys` and `/proc`
    directories.

-   Mounts that enable Systemd, Docker and Kubernetes to operate correctly
    within the system container.
