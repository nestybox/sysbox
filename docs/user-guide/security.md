# Sysbox User Guide: Security

This document describes security aspects of Sysbox system containers.

## Contents

-   [Root Filesystem Jail](#root-filesystem-jail)
-   [Linux Namespaces](#linux-namespaces)
-   [User Namespace ID Mapping](#user-namespace-id-mapping)
-   [Procfs Virtualization](#procfs-virtualization)
-   [Sysfs Virtualization](#sysfs-virtualization)
-   [Process Capabilities](#process-capabilities)
-   [System Calls](#system-calls)
-   [System Call Interception](#system-call-interception)
-   [Devices](#devices)
-   [Resource Limiting & Cgroups](#resource-limiting--cgroups)
-   [No-New-Privileges Flag](#no-new-privileges-flag)
-   [Support for Linux Security Modules (LSMs)](#support-for-linux-security-modules-lsms)
-   [Out-of-Memory Score Adjustment](#out-of-memory-score-adjustment)

## Root Filesystem Jail

System container processes are confined to the directory hierarchy
associated with the container's root filesystem, plus any
configured mounts (e.g., Docker volumes or bind-mounts).

## Linux Namespaces

System containers deployed with Sysbox always use _all_ Linux
namespaces.

That is, when you deploy a system container with Sysbox, (e.g., `docker run
--runtime=sysbox-runc -it alpine:latest`), Sysbox will always use
all Linux namespaces to create the container.

This is done for enhanced container isolation.

It's one area where Sysbox deviates from the OCI specification,
which leaves it to the higher layer (e.g., Docker + containerd) to
choose the namespaces that should be enabled for the container.

The table below shows a comparison on namespace usage between
system containers and regular Docker containers.

| Namespace | Docker + Sysbox | Docker + OCI runc                                                          |
| --------- | --------------- | -------------------------------------------------------------------------- |
| mount     | Yes             | Yes                                                                        |
| pid       | Yes             | Yes                                                                        |
| uts       | Yes             | Yes                                                                        |
| net       | Yes             | Yes                                                                        |
| ipc       | Yes             | Yes                                                                        |
| cgroup    | Yes             | No                                                                         |
| user      | Yes             | No by default; Yes when Docker engine is configured with userns-remap mode |

### User Namespace

By virtue of using the Linux user namespace, system containers get:

-   Stronger container isolation (e.g., root in the container maps to an unprivileged
    user on the host).

-   The root user inside the container has full privileges (i.e., all
    capabilities) within the container.

Refer to the kernel's [user_namespaces](http://man7.org/linux/man-pages/man7/user_namespaces.7.html)
manual page for more info.

### Cgroup Namespace

The Linux cgroup namespace helps isolation by hiding host paths in cgroup
information exposed inside the system container via `/proc`.

Refer to the kernel's [cgroup_namespaces](http://man7.org/linux/man-pages/man7/cgroup_namespaces.7.html)
manual page for more info.

## User Namespace ID Mapping

The Linux user namespace works by mapping user-IDs and group-IDs
between the container and the host.

Sysbox performs the mapping as follows:

-   If the [container manager](concepts.md#container-manager) (e.g., Docker)
    tells Sysbox to run the container with the user-namespace enabled, Sysbox
    honors the user-ID mappings provided by the container manager.

-   Otherwise, Sysbox automatically enables the user-namespace in the container
    and allocates user-ID mappings for it.

We call these "Directed userns ID mapping" and "Auto userns ID mapping"
respectively.

The following sub-sections describe these in further detail.

**Recommendation**:

If your kernel has the `shiftfs` module (you can check by running `lsmod | grep shiftfs`), then
Auto Userns ID Mapping is preferred. Otherwise, you must use Directed Userns ID
Mapping (e.g., by configuring Docker with userns-remap).

### Directed userns ID mapping

When the container manager (e.g., Docker) tells Sysbox to enable
the user-namespace in containers, Sysbox honors the user-ID mappings provided by
the higher layer.

For Docker specifically, this occurs when the Docker daemon is configured with
"userns-remap", as described this [Docker document](https://docs.docker.com/engine/security/userns-remap).

There is one advantage of Directed userns ID mapping:

-   Sysbox does not need the Linux kernel's [shiftfs module](design.md#ubuntu-shiftfs-module).
    This means Sysbox can run in kernels that don't carry that module (e.g.,
    Ubuntu cloud images).

But there is a drawback:

-   Configuring Docker with userns-remap places a few [functional limitations](https://docs.docker.com/engine/security/userns-remap/#user-namespace-known-limitations)
    on regular Docker containers (those launched with Docker's default runc).

### Auto userns ID mapping

When the container manager does not specify the user-namespace for
a container, Sysbox automatically enables it and allocates user-ID mappings for
the container.

For Docker specifically, this occurs when Docker is not configured with
userns-remap (by default, Docker is not configured with userns-remap).

This has the advantage that no change in the configuration of the container
manager (e.g., Docker) is required.

**NOTE**: Sysbox allocates the same user-ID mapping for all system
containers. Exclusive per-container user-ID mappings is considered an
enterprise-level feature (implemented in the Sysbox Enterprise version from
Nestybox).

#### Dependence on Shiftfs

Auto userns ID mapping requires the presence of the [shiftfs module](design.md#ubuntu-shiftfs-module)
in the Linux kernel.

Sysbox will check for this. If the module is required but not present in the
Linux kernel, Sysbox will fail to launch containers and issue an error such as
[this one](troubleshoot.md#ubuntu-shiftfs-module-not-present).

Note that shiftfs is present in Ubuntu Desktop and Server editions, but likely
not present in Ubuntu cloud editions.

## Procfs Virtualization

Sysbox performs partial virtualization of procfs inside the system
container. This is a **key differentiating feature** of Sysbox.

The goal for this virtualization is to expose procfs as read-write yet ensure
the system container processes cannot modify system-wide settings on the host
via procfs.

The virtualization is "partial" because many resources under procfs are already
"namespaced" (i.e., isolated) by the Linux kernel. However, many others are not,
and it is for those that Sysbox performs the virtualization.

The virtualization of procfs inside the container not only occurs on "/proc",
but also in any other procfs mountpoints inside the system container.

By extension, this means that inner containers also see a virtualized procfs,
ensuring they too are well isolated.

Procfs virtualization is independent among system containers, meaning that
each system container gets its own virtualized procfs: any changes it
does to it are not seen in other system containers.

Sysbox takes care of exposing and tracking the procfs contexts within each
system container.

## Sysfs Virtualization

Sysbox performs partial virtualization of sysfs inside the system container, for
the same reasons as with procfs (see prior section).

In addition, the `/sys/fs/cgroup` sub-directory is mounted read-write to allow
system container processes to assign cgroup resources within the system
container. System container processes can only use cgroups to assign a subset of
the resources assigned to the system container itself. Processes inside the
system container can't modify cgroup resources assigned to the system container
itself.

## Process Capabilities

A system container's init process configured with user-ID 0 (root)
always starts with all capabilities enabled.

```console
$ docker run --runtime=sysbox-runc -it alpine:latest
/ # grep -i cap /proc/self/status
CapInh: 0000003fffffffff
CapPrm: 0000003fffffffff
CapEff: 0000003fffffffff
CapBnd: 0000003fffffffff
CapAmb: 0000003fffffffff
```

Note that the system container's Linux user-namespace ensures that these
capabilities are only applicable to resources assigned to the system container
itself. The process has no capabilities on resources not assigned to the system
container.

A system container's init process configured with a non-root user-ID starts with
no capabilities. For example, when deploying system containers with Docker:

```console
$ docker run --runtime=sysbox-runc --user 1000 -it alpine:latest
/ $ grep -i cap /proc/self/status
CapInh: 0000000000000000
CapPrm: 0000000000000000
CapEff: 0000000000000000
CapBnd: 0000003fffffffff
CapAmb: 0000000000000000
```

This mimics the way capabilities are assigned to users on a physical host or VM.

## System Calls

System containers deployed with Sysbox allow a minimum set of 300+ syscalls,
using Linux seccomp.

Significant syscalls blocked within system containers are the
same as those listed [in this Docker article](https://docs.docker.com/engine/security/seccomp/),
except that system container allow these system calls too:

    mount
    umount2
    add_key
    request_key
    keyctl
    pivot_root
    gethostname
    sethostname
    setns
    unshare

It's currently not possible to reduce the set of syscalls allowed within
a system container (i.e., the Docker `--security-opt seccomp=<profile>` option
is not supported).

## System Call Interception

Sysbox performs selective system call interception on a few "control-path"
system calls, such as `mount` and `umount2`.

This is another key feature of Sysbox, and it's done in order to perform proper
[procfs](#procfs-virtualization) and [sysfs](#sysfs-virtualization)
virtualization.

Sysbox does this very selectively in order to ensure performance of processes
inside the system container is not impacted.

## Devices

The following devices are always present in the system container:

    /dev/null
    /dev/zero
    /dev/full
    /dev/random
    /dev/urandom
    /dev/tty

Additional devices may be added by the container engine. For example,
when deploying system containers with Docker, you typically see the
following devices in addition to the ones listed above:

    /dev/console
    /dev/pts
    /dev/mqueue
    /dev/shm

Sysbox does not currently support exposing host devices inside system
containers (e.g., via the `docker run --device` option). We are
working on adding support for this.

## Resource Limiting & Cgroups

System container resource consumption can be limited via cgroups.

This can be used to balance resource consumption as well as to prevent
denial-of-service attacks in which a buggy or compromised system
container consumes all available resources in the system.

For example, when using Docker to deploy system containers, the
`docker run --cpu*`, `--memory*`, `--blkio*`, etc., settings can be
used for this purpose.

## No-New-Privileges Flag

Modern versions of the Linux kernel (>= 3.5) support a per-process
attribute called `no_new_privs`.

It's a security feature meant to ensure a child process can't gain more
privileges than its parent process.

Once this attribute is set on a process it can't be unset, and it's inherited by
all child and further descendant processes.

The details are explained [here](https://www.kernel.org/doc/Documentation/prctl/no_new_privs.txt) and
[here](http://man7.org/linux/man-pages/man2/prctl.2.html).

The `no_new_privs` attribute may be set on the init process of a
container, for example, using the `docker run --security-opt no-new-privileges`
flag (see the [docker run](https://docs.docker.com/engine/reference/run/)
doc for details).

In a system container, the container's init process is normally owned by the
system container's root user and granted full privileges within the system
container's user namespace (as described [above](#process-capabilities)).

In this case setting the `no_new_privs` attribute on the system container's init
process has no effect as far as limiting the privileges it may get (since it
already has all privileges within the system container).

However, it does have effect on child processes with lesser privileges (those
won't be allowed to elevate their privileges, preventing them from executing
setuid programs for example).

## Support for Linux Security Modules (LSMs)

### AppArmor

Sysbox does not yet support AppArmor profiles to apply mandatory
access control (MAC) to containers.

If the container manager (e.g., Docker) instructs Sysbox to apply
an AppArmor profile on a container, Sysbox currently ignores this.

The rationale behind this is that typical AppArmor profiles from container
managers such as Docker are too restrictive for system containers, and don't
give you much benefit given that Sysbox gets equivalent protection by enabling the
Linux user namespaces in its containers.

For example, Docker's [default AppArmor profile](https://docs.docker.com/engine/security/apparmor/)
is too restrictive for system containers.

Having said this, in the near future we plan to add some support for AppArmor in
order to follow the defense-in-depth security principle.

### SELinux

Sysbox does not yet support running on systems with SELinux enabled.

### Other LSMs

Sysbox does not have support for other Linux LSMs at this time.

## Out-of-Memory Score Adjustment

The Linux kernel has a mechanism to kill processes when the
system is running low on memory.

The decision on which process to kill is done based on an
out-of-memory (OOM) score assigned to all processes.

The score is in the range [-1000:1000], where higher values means higher
probability of the process being killed when the host reaches an out-of-memory
scenario.

It's possible for users with sufficient privileges to adjust the OOM
score of a given process, via the `/proc/[pid]/oom_score_adj` file.

A system container's init process OOM score adjustment can be
configured to start at a given value. For example, using Docker's `--oom-score-adj` option:

```console
$ docker run --runtime=sysbox-runc --oom-score-adj=-100 -it alpine:latest
```

In addition, Sysbox ensures that system container processes are
allowed to modify their out-of-memory (OOM) score adjustment to any
value in the range [-999:1000], via `/proc/[pid]/oom_score_adj`.

This is necessary in order to allow system software that requires such
adjustment range (e.g., Kubernetes) to operate correctly within the system
container.

From a host security perspective however, allowing system container
processes to adjust their OOM score downwards is risky, since it
means that such processes are unlikely to be killed when the host is
running low on memory.

To mitigate this risk, a user can always put an upper bound on the
memory allocated to each system container. Though this does not
prevent a system container process from reducing its OOM score,
placing such an upper bound reduces the chances of the system
running out of memory and prevents memory exhaustion attacks
by malicious processes inside the system container.

Placing an upper bound on the memory allocated to the system container
can be done by using Docker's `--memory` option:

```console
$ docker run --runtime=sysbox-runc --memory=100m -it alpine:latest
```
