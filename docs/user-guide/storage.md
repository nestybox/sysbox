# Sysbox User Guide: Mounting and Sharing Host Storage

This document provides tips on mounting host storage into one or more system containers.

## Contents

-   [Exposing Host Files or Directories Inside a System Container](#exposing-host-files-or-directories-inside-a-system-container)
    -   [The Problem](#the-problem)
    -   [The Solution](#the-solution)
    -   [Host Supports User and Group ID Shifting (shiftfs)](#host-supports-user-and-group-id-shifting-shiftfs)
    -   [Host does not support User and Group ID Shifting (i.e., no shiftfs)](#host-does-not-support-user-and-group-id-shifting-ie-no-shiftfs)
-   [Storage Sharing Among System Containers](#storage-sharing-among-system-containers)

## Exposing Host Files or Directories Inside a System Container

Sysbox system containers support all Docker storage mount types:
[volume, bind, or tmpfs](https://docs.docker.com/storage/).

However, for bind mounts there are requirements in order to deal with
file ownership issues.

    Note: these requirements apply specifically to bind-mounts. They do not
    apply to Docker volume or tmpfs mounts, as they are implicitly met by them
    (i.e., you don't have to worry about file ownership issues for them).
    They also do not apply to the container's root filesystem, which is
    automatically setup to always have the correct ownership.

Bind mounts provide a mechanism for users to expose a host file or directory
inside the container. For example, this creates a Sysbox system container with
a bind mount of host directory `my-host-dir` exposed in the container's `/mnt/my-host-dir`.

```console
$ docker run --runtime=sysbox-runc -it --mount type=bind,source=my-host-dir,target=/mnt/my-host-dir alpine
```

The concept is simple, but file ownership issues arise because Sysbox always
isolates containers via the Linux user-namespace, as described below.

### The Problem

These file ownership issues arise from the fact that Sysbox system containers
always use the Linux user-namespace, which means that the container's user and
group IDs are mapped to a range of unpriviliged host IDs.

For example, a given system container's user and group IDs may be mapped as
follows:

| Container ID  | Host ID        |
| :-----------: | :------------: |
| 0 -> 65535    | 100000->165535 |

In other words, user 0 inside the container maps to user 100000 on the host,
user 1 maps to user 100001, and so on.

This implies that host files owned by users 100000->165535 will show up as
owned by users 0->65535 in the container, but host files owned by other
users will show up as owned by "nobody:nogroup" inside the container.

But for bind mounts that's not good, because a host admin can't always know
the Linux user-namespace mappings that will be assigned to a container,
so he or she can't set the host level file ownership properly.

The mappings are either chosen by a container manager such as Docker (e.g., when
Docker operates in userns-remap mode) or otherwise automatically selected by
Sysbox.

Furthermore, when the mappings are automatically selected by Sysbox, the
mappings can be exclusive between containers (as with Sysbox Enterprise), and
multiple containers with different mappings may want to share a given host
directory or file.

### The Solution

Ideally, host files with ownership 0->65535 that are bind-mounted into a system
container would show up inside the system container with that same ownership
(just as they do for containers that don't use the Linux user-namespace). This
way the host admin need not worry about what host IDs are mapped to the
container via the Linux user-namespace.

Sysbox has a feature that implements this solution, but it requires that the
Linux distro support "ID shifting" (i.e., via the `shiftfs` kernel module).

    NOTE: Currently, only Ubuntu supports the shiftfs kernel module.

For distros that do not support shiftfs, the host admin must configure the
user and group ID ownership of the bind mounted volumes.

The sections below explain both of these scenarios.

### Host Supports User and Group ID Shifting (shiftfs)

For Linux distros that support the shiftfs kernel module (e.g., Ubuntu), Sysbox
leverages this functionality to automatically deal with file ownership issues on
bind-mounts.

That is, Sysbox automatically mounts shiftfs on the host directories that are
bind mounted into the container when it deems it necessary to ensure that files
show up inside the container with appropriate ownership.

For example, if we have a host directory called `my-host-dir` where files
are owned by users in the range [0:65536], and that directory is bind mounted
into a system container as follows:

```console
$ docker run --runtime=sysbox-runc -it --mount type=bind,source=my-host-dir,target=/mnt/my-host-dir alpine
```

then Sysbox will mount shiftfs on `my-host-dir`, causing the files to show up
with the same ownership ([0:65536]) inside the container, even though the
container's user-IDs and group-IDs are mapped to a completely different set of
IDs on the host (e.g., 100000->165536).

This way, a host admin need not worry about what host IDs are mapped into the
container via the Linux user-namespace. Sysbox takes care of setting things up so
that the bind mounted files show up with proper permissions inside the
container. Moreover, containers with exclusive user-namespace ID mappings (as
assigned by Sysbox-EE for extra isolation) can share the same files on the host
without problem.

This is the recommended mode of operation, though some security precautions
and limitations apply as described below.

#### Security Precautions with Shiftfs

The use of shiftfs requires some security precautions:

1.  The bind mounted file or directory should be in a directory that is only
    accessible to the host's root user (i.e., 0700 permissions somewhere in its
    path).

2.  Alternatively, it should be bind-mounted read-only in the container.

For example, in the following command:

```console
$ docker run --runtime=sysbox-runc --mount type=bind,source=/some/source,target=/some/target ...
```

directory `/some/source` should have 0700 on `/some` or `/some/source`. If this is not
possible, mount it read-only:

```console
$ docker run --runtime=sysbox-runc --mount type=bind,source=/some/source,target=/some/target,readonly ...
```

The reason for these precautions is that when a root process inside the system
container writes to the bind-mounted directories, it will be doing so
`root:root` privileges on the host (due to the shiftfs mount). Thus, you want to
avoid any non-root user on the host having access to those directories.

The above security precautions are optional. Sysbox won't check for them (i.e.,
if they aren't met the system container will still work).

However, failure to meet one of these requirements will result in reduced host
security as described [here](design.md#shiftfs-security-precautions).

#### Limitations with Shiftfs

There are some limitations that arise on host files or directories bind mounted
into system container when Sysbox uses shiftfs.

1.  Host directories bind mounted into the system container become
    "no-executable" at host level. This is a security precaution (inherent to
    shiftfs) to prevent files written by the container on the bind mounted
    directory from being executed at host level (since those files may have root
    ownership for example).

2.  The bind mount should ideally be done on a directory (rather than on a single
    file). If done on a file, it will work, but Sysbox will mount shiftfs on
    the parent directory (due to a limitation of shiftfs), which is not ideal.

3.  Some critical host directories can't be bind-mounted into the container.

    These are: "/", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/local/bin", "/usr/local/sbin", "/dev", "/run", "/var/run".

    The reason is that mounting shiftfs on these directories will render the
    host unusable because the directories will become non-executable. Thus,
    Sysbox will never mount shiftfs on these directories. If you bind-mount
    these into the container, their contents will show up as "nobody:nogroup"
    in the container. Note that even without shiftfs, such a bind mounts are
    not wise as they break container to host isolation.

4.  Host directories directly above the container's rootfs can't be bind-mounted
    to the container. For example, when using Docker, the container's rootfs
    lives under `/var/lib/docker/...`. Thus, it's not possible to bind mount
    the host's "/", "/var", "/var/lib", and "/var/lib/docker" to the container.
    It it possible to mount "/x", "/var/x", "/var/lib/x" into the container,
    since in those cases "x" is not directly above the container's rootfs directory.
    Note that even without shiftfs, bind mounting directories directly above
    the container's rootfs is not advisable as it would break container isolation.

#### Disabling shiftfs on bind-mounts

For scenarios where a host supports shiftfs but users don't wish Sysbox
to mount shiftfs on bind mount sources, the sysbox-mgr has a command
line option to disable this (`--bind-mount-id-shift=false`).

Refer to the [Sysbox configuration doc](configuration.md) for further info on
how to apply this setting.

### Host does not support User and Group ID Shifting (i.e., no shiftfs)

For Linux distros that do not support the shiftfs kernel module (e.g., RHEL,
Fedora), the solution described in the prior section does not apply
(unfortunately).

As a result, dealing with permissions on bind mounts is harder.

In such distros, when bind mounting a file into the container, the user must
determine the host IDs mapped to the container's Linux user-namespace and set
the ownership of the files appropriately.

But what host user and group ID is that? Well, that depends on the user-ID range
that Sysbox assigns to the container.

As described [here](security.md#user-namespace-id-mapping), either:

-   Sysbox is told the user-ID mapping of the container by a container manager such as Docker (aka [Directed userns ID mapping](security.md#directed-userns-id-mapping))

or

-   Sysbox auto-assigns the user-ID mapping of the container (aka [Auto userns ID mapping](security.md#auto-userns-id-mapping))

The sections below explain these two sub-cases.

#### Directed userns ID mapping

When Sysbox is told the user-ID mapping of the container, the container manager
above Sysbox (e.g., Docker) chooses the user-ID mapping.

For example, when Docker is configured with
[userns-remap](https://docs.docker.com/engine/security/userns-remap/), it
chooses the user-ID mapping of the container and instructs Sysbox to use it.

In this case, you can find the user-ID to assign to the bind mount source as
follows:

1.  Inspect the Docker daemons userns-remap configuration:

```console
$ cat /etc/docker/daemon.json
{
   "userns-remap": "someuser",
   ...
}
```

2.  Find the subuid and subgid ranges for `someuser` in the `/etc/subuid` and
    `/etc/subgid` files.

```console
$ cat /etc/subuid
someuser:100000:65536
sysbox:165536:268435456

$ cat /etc/subgid
someuser:100000:65536
sysbox:165536:268435456
```

3.  The bind mount source should be owned by user-ID in the range \[100000:165535].
    Same for the group-ID.

For example, in the following command:

    docker run --runtime=sysbox-runc --mount type=bind,source=/some/source,target=/some/target ...

if the directory `/some/source` is owned by `100000:100000` on the host, it will
show up as `root:root` inside the container. If it's owned by `101000:101000`,
it will show up as user `1000:1000` inside the container. And so on.

#### Auto userns ID mapping

When Sysbox is not told the user-ID mapping of the container by a container
manager (e.g., Docker), Sysbox automatically assigns the container's user-ID
mappings.

Note that by default Docker is configured without
[userns-remap](https://docs.docker.com/engine/security/userns-remap/), causing
Sysbox to auto assign the container user-ID mappings.

In this case, you can find the user-ID to assign to the bind mount source as
follows:

For Sysbox Community Edition (Sysbox-CE):

1.  Sysbox always assigns the same user-ID and group-ID mapping to all containers.

2.  The user and group ID are obtained by looking at the entry for user `sysbox` in
    the `/etc/subuid` and `/etc/subgid` files.

```console
$ cat /etc/subuid
someuser:100000:65536
sysbox:165536:65536

$ cat /etc/subgid
someuser:100000:65536
sysbox:165536:65536
```

3.  The bind mount source should be owned by user-ID in the range \[165536:231071].
    Same for the group-ID. They will show up as \[0:65535] inside the container.

For Sysbox Enterprise Edition (Sysbox-EE):

1.  Sysbox-EE assigns exclusive user-ID and group-ID mapping to each container.

    This presents a problem for bind mount ownership in host's where shiftfs is
    not supported, because the host admin can't tell what host IDs will be
    assigned to the container (and therefore can't tell what ownership should the
    bind-mounted files have).

2.  To deal with this, the work-around is to restrict the range of user and group
    ID mappings that Sysbox-EE assigns, such that all containers get the
    same mapping (i.e., to resemble the operation of Sysbox-CE).

3.  This is done by modifying the `/etc/subuid` and `/etc/subgid` files
    to restrict the range of subuids assigned to Sysbox to 65536:

```console
$ cat /etc/subuid
someuser:100000:65536
sysbox:165536:65536

$ cat /etc/subgid
someuser:100000:65536
sysbox:165536:65536
```

5.  Note that a restart of Sysbox-EE is required, so that it will pick up
    the new settings in `/etc/subuid` and `/etc/subgid`.

6.  After this, the bind mount source should be owned by user-ID in the range
    [165536:231071].  Same for the group-ID. This way they will show up as
    [0:65535] inside the container.

## Storage Sharing Among System Containers

In order to share storage between multiple system containers, simply run the
system containers and bind mount the shared storage into them.

When performing the bind-mount, make sure to follow the requirements described in
the [prior section](#exposing-host-files-or-directories-inside-a-system-container).

The Sysbox Quick Start Guide has an example of multiple system containers
sharing storage [here](../quickstart/storage.md#sharing-storage-among-system-containers).
