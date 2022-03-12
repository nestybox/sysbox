# Sysbox User Guide: Design Notes

This document briefly describes some aspects of Sysbox's design.

## Contents

-   [Sysbox Components](#sysbox-components)
-   [ID-Mapped Mounts \[ v0.5.0+ \]](#id-mapped-mounts--v050-)
-   [Shiftfs Module](#shiftfs-module)
-   [Overlayfs mounts inside the Sysbox Container](#overlayfs-mounts-inside-the-sysbox-container)
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

Users don't normally interact with the Sysbox components directly. Instead,
they use higher level apps (e.g., Docker) that interact with Sysbox to deploy
system containers.

## ID-Mapped Mounts \[ v0.5.0+ ]

The Linux kernel >= 5.12 includes a feature called "ID-Mapped mounts" that
allows remapping of the user and group IDs of files. It was developed primarily
by Christian Brauner at Canonical (to whom we owe a large debt of gratitude).

Starting with version 0.5.0, Sysbox leverages this feature to to perform
filesystem user-ID and group-ID mapping between the container's Linux user
namespace and the host's initial user namespace.

For example, inside a Sysbox container, user-ID range 0->65535 is always mapped
to unprivileged user-ID range at host level chosen by Sysbox (e.g.,
100000->165535) via the Linux user-namespace. This way, container processes
are fully unprivileged at host level.

However, this mapping implies that if a host file with user-ID 1000 is mounted
into the container, it will show up as `nobody:nogroup` inside the container
given that user-ID 1000 is outside of the range 100000->165536.

The kernel's "ID-mapped mounts" feature solves this problem. It allows Sysbox to
ask the kernel to remap the user-IDs (and group-IDs) for host files mounted into
the container. Following the example above, a host file with user-ID 1000 will
now show up inside the container with user-ID 1000 too, as the kernel will map
user-ID 1000->101000 (and vice-versa).

This is beneficial, because from a user's perspective you don't need to worry
about what user-namespace mappings have been assigned by Sysbox to the
container. It also means you can now share files between the host and the
container, or between containers without problem, while enjoying the extra
isolation & security provided by the Linux user-namespace.

Refer to the [User Guide's Storage Chapter](storage.md) for more info.

### ID-mapped Mounts Functional Limitations

The Ubuntu shiftfs module is very recent and therefore has some
functional limitations as this time.

One such limitation is that ID-mapped mounts can't be mounted on top file or
directories backed by specialized filesystems (e.g., overlayfs, device files).

Sysbox understands these limitations and takes appropriate action to
overcome them. One such action is to use the kernel's shiftfs module
(when available) as described in the next section.

## Shiftfs Module

Recent Ubuntu kernels carry a module called `shiftfs`. The purpose of this
module is to perform filesystem user-ID and group-ID remapping between the
container's Linux user namespace and the host's initial user namespace,
similar to ID-mapped mounts (see [prior section](#ID-mapped-mounts--v050-).

Shiftfs predates the ID-mapped mounts feature but it's not a standard mechanism.
It's only supported on Ubuntu, Debian, and Flatcar, and in the latter two it
must be installed manually (i.e., it's not included in the kernel).

It is expected that over time ID-mapped mounts will fully replace shiftfs,
although as of early 2022 shiftfs still has some advantages over ID-mapped
mounts, such as ID-mapping on top of overlayfs (which is important since the
container's root filesystem is typically on overlayfs).

Sysbox detects the presence of the shiftfs module and uses it when appropriate.

### Checking for the Shiftfs Module

To verify the Ubuntu shiftfs module is loaded in your host, type:

```console
$ sudo modprobe shiftfs
$ lsmod | grep shiftfs
shiftfs           24576  0
```

## Overlayfs mounts inside the Sysbox Container

It is common to run containers (e.g., Docker) inside a Sysbox container.
These inner containers often use overlayfs, which means that overlayfs
mounts will be set up inside the Sysbox container (which is itself
on an overlayfs mount).

Since it's not possible to stack overlayfs mounts, Sysbox works around this by
creating implicit host mounts into the Sysbox container on specific directories
where overlayfs mounts are known to take place, such as inside the container's
`/var/lib/docker`, `/var/lib/kubelet`, and other similar directories.  These
mounts are managed by Sysbox, which understands when to create and destroy them.

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

By default, Sysbox assigns process capabilities in the container as
follows:

-   Enables all process capabilities for the system container's init process when
    owned by the root user.

-   Disables all process capabilities for the system container's init process when
    owned by a non-root user.

This mimics the way capabilities are assigned to processes on a physical host or
VM. See the [security chapter](security.md#process-capabilities) for more on this.

Note that starting with Sysbox v0.5.0, it's possible to modify this behavior to
have Sysbox honor the capabilities passed to it by the higher level container
manager via the OCI spec. See the [configuration chapter](configuration.md) for
more on this.

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
