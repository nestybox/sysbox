# Sysbox User Guide: Mounting and Sharing Host Storage

This document provides tips on mounting host storage into one or more system containers.

## Contents

-   [System Container Bind Mount Requirements](#system-container-bind-mount-requirements)
-   [Storage Sharing Among System Containers](#storage-sharing-among-system-containers)

## System Container Bind Mount Requirements

Sysbox system containers support all Docker storage mount types:
[volume, bind, or tmpfs](https://docs.docker.com/storage/).

However, for bind mounts there are important requirements in order to deal with
file ownership issues.

    Note: these requirements don't apply to Docker volume or tmpfs mounts, as they
    are implicitly met by them.

The rule is simple: the host file or directory that is bind-mounted into the container
should be owned by a user-ID that makes sense within the container.

But what user-ID is that? Well, that depends on the user-ID range that Sysbox assigns to
the container.

As described [here](security.md#user-namespace-id-mapping), either:

-   Sysbox is told the user-ID mapping of the container by a container manager such as Docker (aka [Directed userns ID mapping](security.md#directed-userns-id-mapping))

or

-   Sysbox auto-assigns the user-ID mapping of the container (aka [Auto userns ID mapping](security.md#auto-userns-id-mapping))

### Directed userns ID mapping

When Sysbox is told the user-ID mapping of the container, the container manager
chooses the user-ID mapping.

For example, when Docker is configured with
[userns-remap](https://docs.docker.com/engine/security/userns-remap/), it
chooses the user-ID mapping of the container and instructs Sysbox to use it.

In this case, you can find the user-ID to assign to the bind mount source as
follows:

1) Inspect the Docker daemons userns-remap configuration:

```console
$ cat /etc/docker/daemon.json
{
   "userns-remap": "someuser",
   ...
}
```

2) Find the subuid and subgid ranges for `someuser` in the `/etc/subuid` and
   `/etc/subgid` files.

```console
$ cat /etc/subuid
someuser:100000:65536
sysbox:165536:268435456

$ cat /etc/subgid
someuser:100000:65536
sysbox:165536:268435456
```

3) The bind mount source should be owned by user-ID in the range [100000:165535].
   Same for the group-ID.

For example, in the following command:

    docker run --runtime=sysbox-runc --mount type=bind,source=/some/source,target=/some/target ...

if the directory `/some/source` is owned by `100000:100000` on the host, it will
show up as `root:root` inside the container. If it's owned by `101000:101000`,
it will show up as user `1000:1000` inside the container. And so on.

### Auto userns ID mapping

When Sysbox is not told the user-ID mapping of the container by a container
manager (e.g., Docker), it automatically assigns the container's user-ID
mappings.

For example, by default Docker is configured without [userns-remap](https://docs.docker.com/engine/security/userns-remap/),
causing Sysbox to auto assign the container user-ID mappings.

In this case, the rule for bind mount ownership is simple: the bind mount source
should be owned by a user in the range [0:65536], and will appear inside the
container with that same ownership (i.e., identity-mapped).

For example, in the following command:

```console
$ docker run --runtime=sysbox-runc --mount type=bind,source=/some/source,target=/some/target ...
```

if the directory `/some/source` is owned by `root:root` on the host, it will show up as `root:root`
inside the container. If it's owned by `1000:1000` on the host, it will show up as
user `1000:1000` inside the container. And so on.

### Shiftfs and Security Precautions

When doing auto userns ID mapping, Sysbox mounts the `shiftfs` filesystem on
all host directories that are bind-mounted into the container.

    Note: this does not apply for Directed userns ID mapping.

The shiftfs mount is required in order for the bind mounted directory to appear
with proper ownership inside the container.

However, the use of shiftfs requires some security precautions:

1) The bind mounted file or directory should be in a directory that is only
   accessible to the host's root user (i.e., 0700 permissions somewhere in its
   path).

2) Alternatively, it should be bind-mounted read-only in the container.

For example, in the following command:

```console
$ docker run --runtime=sysbox-runc --mount type=bind,source=/some/source,target=/some/target ...
```

directory `/some/source` should have 0700 on `/some` or `/some/source`. If this is not
possible, mount it read-only:

```console
$ docker run --runtime=sysbox-runc --mount type=bind,source=/some/source,target=/some/target,readonly ...
```

The reason for these precautions is that when the processes inside the system
container write to the bind-mounted directories, they will be doing so
`root:root` privileges on the host. Thus, you want to avoid any non-root user on
the host having access to those directories.

The above security precautions are optional. Sysbox won't check for them (i.e.,
if they aren't met the system container will still work).

However, failure to meet one of these requirements will result in reduced host
security as described [here](design.md#shiftfs-security-precautions).

## Storage Sharing Among System Containers

System containers use the Linux user-namespace for increased isolation from the
host and from other containers.

A known issue with containers that use the user-namespace is that sharing
storage between them is not trivial because each container may be assigned an
exclusive user-ID(group-ID) range on the host, and thus may not have permissions
to access the files in the shared storage (unless such storage has lax
permissions allowing read-write-execute by any user).

Sysbox system containers support storage sharing between multiple system
containers, without lax permissions and in spite of the fact that each system
container may be assigned an exclusive user-ID/group-ID range on the host.

In order to share storage between multiple system containers, simply run the
system containers and bind mount the storage into them.

When performing the bind-mount, make sure to follow the requirements described in
the [prior section](#system-container-bind-mount-requirements).

The Sysbox Quick Start Guide has an example of multiple system containers
sharing storage [here](../quickstart/storage.md#sharing-storage-among-system-containers).
