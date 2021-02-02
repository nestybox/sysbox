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
-   [System Call Interception \[ +v0.2.0 \]](#system-call-interception--v020-)
-   [Devices](#devices)
-   [Resource Limiting & Cgroups](#resource-limiting--cgroups)
-   [Initial Mount Immutability \[ +v0.3.0 \]](#initial-mount-immutability--v030-)
-   [No-New-Privileges Flag](#no-new-privileges-flag)
-   [Support for Linux Security Modules (LSMs)](#support-for-linux-security-modules-lsms)
-   [Out-of-Memory Score Adjustment](#out-of-memory-score-adjustment)

## Root Filesystem Jail

System container processes are confined to the directory hierarchy
associated with the container's root filesystem, plus any
configured mounts (e.g., Docker volumes or bind-mounts).

This is known as the container's root filesystem jail (aka "rootfs jail").

## Linux Namespaces

System containers deployed with Sysbox always use *all* Linux
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
userns-remap (which is normally the case).

This has the advantage that no change in the configuration of the container
manager (e.g., Docker) is required, so it can continue to launch regular
containers (i.e., with the OCI runc) as usual while at the same time launch
system containers with Sysbox.

#### Dependence on Shiftfs

Auto userns ID mapping requires the presence of the [shiftfs module](design.md#ubuntu-shiftfs-module)
in the Linux kernel.

Sysbox will check for this. If the module is required but not present in the
Linux kernel, Sysbox will fail to launch containers and issue an error such as
[this one](troubleshoot.md#ubuntu-shiftfs-module-not-present).

Note that shiftfs is present in Ubuntu Desktop and Server editions, but likely
not present in Ubuntu cloud editions.

### Common vs Exclusive Userns ID Mappings

The Sysbox Community Edition (Sysbox-CE) uses a common user-ID mapping for all
system containers. In other words, the root user in all containers is mapped to
the same user-ID on the host.

While this provides strong container-to-host isolation (i.e., root in the
container is not root in the host), container-to-container is not as strong as
it could be.

The Sysbox Enterprise Edition (Sysbox-EE) improves on this by providing
exclusive user-ID mappings to each container.

#### **-------- Sysbox-EE Feature Highlight --------**

### Exclusive Userns ID mapping allocation

In order to provide strong cross-container isolation, Sysbox-EE allocates
exclusive userns ID mappings to each container,

By way of example: if we launch two containers with Sysbox-EE, notice the ID
mappings assigned to each:

    $ docker run --runtime=sysbox-runc --name=syscont1 --rm -d alpine tail -f /dev/null
    16c1abcc48259a47ef749e2d292ceef6a9f7d6ab815a6a5d12f06efc3c09d0ce

    $ docker run --runtime=sysbox-runc --name=syscont2 --rm -d alpine tail -f /dev/null
    573843fceac623a93278aafd4d8142bf631bc1b214b1bcfcd183b1be77a00b69

    $ docker exec syscont1 cat /proc/self/uid_map
    0     165536      65536

    $ docker exec syscont2 cat /proc/self/uid_map
    0     231072      65536

Each system container gets an **exclusive range of 64K user IDs**. For syscont1,
user IDs [0, 65536] are mapped to host user IDs [165536, 231071]. And for
syscont2 user IDs [0, 65536] are mapped to host user IDs [231072, 65536].

The same applies to the group IDs.

The reason 64K user-IDs are given to each system container is to allow the
container to have IDs ranging from the `root` (ID 0) all the way up to user
`nobody` (ID 65534).

Exclusive ID mappings ensure that if a container process somehow escapes the
container's root filesystem jail, it will find itself without any permissions to
access any other files in the host or in other containers.

#### Userns ID Mapping Range

The exclusive host user IDs chosen by Sysbox-EE are obtained from the `/etc/subuid`
and `/etc/subgid` files:

    $ more /etc/subuid
    cesar:100000:65536
    sysbox:165536:268435456

    $ more /etc/subgid
    cesar:100000:65536
    sysbox:165536:268435456

These files are automatically configured by Sysbox during installation (or more
specifically when the `sysbox-mgr` component is started during installation)

By default, Sysbox reserves a range of 268435456 user IDs (enough to accommodate
4K system containers, each with 64K user IDs).

If more than 4K containers are running at the same time, Sysbox will by default
re-use user-ID mappings from the range specified in `/etc/subuid`. The same
applies to group-ID mappings. In this scenario multiple system containers may
share the same user-ID mapping, reducing container-to-container isolation a bit.

For extra security, it's possible to configure Sysbox to not re-use mappings and
instead fail to launch new system containers until host user IDs become
available (i.e., when other system containers are stopped).

The size of the reserved ID range, as well as the policy in case the range is
exhausted, is configurable via the sysbox-mgr command line.  If you wish to
change this, See `sudo sysbox-mgr --help` and use the [Sysbox reconfiguration procedure](configuration.md#reconfiguration-procedure).

#### **----------------------------------------------------------**

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

## System Call Interception \[ +v0.2.0 ]

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

## Initial Mount Immutability \[ +v0.3.0 ]

Filesystem mounts that make up the [system container's rootfs jail](#root-filesystem-jail)
(i.e., mounts setup at container creation time) are considered special, meaning
that Sysbox places restrictions on the operations that may be done on them from
within the container.

This ensures processes inside the container can't modify those mounts in a way
that would weaken or break container isolation, even though these processes may
be running as root with full capabilities inside the container and thus have
access to the `mount` and `umount` syscalls.

We call these "immutable mounts".

For example, assume we launch a system container with a read-only mount of a host
Docker volume called `myvol`:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname=syscont -v myvol:/mnt/myvol:ro ubuntu
root@syscont:/#
```

Inside the container, you'll see that the root filesystem is made up
of several mounts setup implicitly by Sysbox, as well as the `myvol` mount:

```console
root@syscont:/# findmnt
TARGET                                                       SOURCE                                                                                                    FSTYPE   OPTIONS
/                                                            .                                                                                                         shiftfs  rw,relatime
|-/sys                                                       sysfs                                                                                                     sysfs    rw,nosuid,nodev,noexec,relatime
| |-/sys/firmware                                            tmpfs                                                                                                     tmpfs    ro,relatime,uid=165536,gid=165536
| |-/sys/fs/cgroup                                           tmpfs                                                                                                     tmpfs    rw,nosuid,nodev,noexec,relatime,mode=755,uid=165536,gid=165536
| | |-/sys/fs/cgroup/systemd                                 systemd                                                                                                   cgroup   rw,nosuid,nodev,noexec,relatime,xattr,name=systemd
| | |-/sys/fs/cgroup/memory                                  cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,memory
| | |-/sys/fs/cgroup/cpuset                                  cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,cpuset
| | |-/sys/fs/cgroup/blkio                                   cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,blkio
| | |-/sys/fs/cgroup/net_cls,net_prio                        cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,net_cls,net_prio
| | |-/sys/fs/cgroup/perf_event                              cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,perf_event
| | |-/sys/fs/cgroup/hugetlb                                 cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,hugetlb
| | |-/sys/fs/cgroup/cpu,cpuacct                             cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,cpu,cpuacct
| | |-/sys/fs/cgroup/freezer                                 cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,freezer
| | |-/sys/fs/cgroup/devices                                 cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,devices
| | |-/sys/fs/cgroup/pids                                    cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,pids
| | `-/sys/fs/cgroup/rdma                                    cgroup                                                                                                    cgroup   rw,nosuid,nodev,noexec,relatime,rdma
| |-/sys/kernel/config                                       tmpfs                                                                                                     tmpfs    rw,nosuid,nodev,noexec,relatime,size=1024k,uid=165536,gid=165536
| |-/sys/kernel/debug                                        tmpfs                                                                                                     tmpfs    rw,nosuid,nodev,noexec,relatime,size=1024k,uid=165536,gid=165536
| |-/sys/kernel/tracing                                      tmpfs                                                                                                     tmpfs    rw,nosuid,nodev,noexec,relatime,size=1024k,uid=165536,gid=165536
| `-/sys/module/nf_conntrack/parameters/hashsize             sysboxfs[/sys/module/nf_conntrack/parameters/hashsize]                                                    fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
|-/proc                                                      proc                                                                                                      proc     rw,nosuid,nodev,noexec,relatime
| |-/proc/bus                                                proc[/bus]                                                                                                proc     ro,relatime
| |-/proc/fs                                                 proc[/fs]                                                                                                 proc     ro,relatime
| |-/proc/irq                                                proc[/irq]                                                                                                proc     ro,relatime
| |-/proc/sysrq-trigger                                      proc[/sysrq-trigger]                                                                                      proc     ro,relatime
| |-/proc/asound                                             tmpfs                                                                                                     tmpfs    ro,relatime,uid=165536,gid=165536
| |-/proc/acpi                                               tmpfs                                                                                                     tmpfs    ro,relatime,uid=165536,gid=165536
| |-/proc/keys                                               udev[/null]                                                                                               devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/proc/timer_list                                         udev[/null]                                                                                               devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/proc/sched_debug                                        udev[/null]                                                                                               devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/proc/scsi                                               tmpfs                                                                                                     tmpfs    ro,relatime,uid=165536,gid=165536
| |-/proc/swaps                                              sysboxfs[/proc/swaps]                                                                                     fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
| |-/proc/sys                                                sysboxfs[/proc/sys]                                                                                       fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
| `-/proc/uptime                                             sysboxfs[/proc/uptime]                                                                                    fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
|-/dev                                                       tmpfs                                                                                                     tmpfs    rw,nosuid,size=65536k,mode=755,uid=165536,gid=165536
| |-/dev/console                                             devpts[/0]                                                                                                devpts   rw,nosuid,noexec,relatime,gid=165541,mode=620,ptmxmode=666
| |-/dev/mqueue                                              mqueue                                                                                                    mqueue   rw,nosuid,nodev,noexec,relatime
| |-/dev/pts                                                 devpts                                                                                                    devpts   rw,nosuid,noexec,relatime,gid=165541,mode=620,ptmxmode=666
| |-/dev/shm                                                 shm                                                                                                       tmpfs    rw,nosuid,nodev,noexec,relatime,size=65536k,uid=165536,gid=165536
| |-/dev/kmsg                                                udev[/null]                                                                                               devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/dev/null                                                udev[/null]                                                                                               devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/dev/random                                              udev[/random]                                                                                             devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/dev/full                                                udev[/full]                                                                                               devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/dev/tty                                                 udev[/tty]                                                                                                devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| |-/dev/zero                                                udev[/zero]                                                                                               devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
| `-/dev/urandom                                             udev[/urandom]                                                                                            devtmpfs rw,nosuid,noexec,relatime,size=1971180k,nr_inodes=492795,mode=755
|-/mnt/myvol                                                 /var/lib/docker/volumes/myvol/_data                                                                       shiftfs  ro,relatime
|-/etc/resolv.conf                                           /var/lib/docker/containers/080fb5dbe347a947accf7ba27a545ce11d937f02f02ec0059535cfc065d04ea0[/resolv.conf] shiftfs  rw,relatime
|-/etc/hostname                                              /var/lib/docker/containers/080fb5dbe347a947accf7ba27a545ce11d937f02f02ec0059535cfc065d04ea0[/hostname]    shiftfs  rw,relatime
|-/etc/hosts                                                 /var/lib/docker/containers/080fb5dbe347a947accf7ba27a545ce11d937f02f02ec0059535cfc065d04ea0[/hosts]       shiftfs  rw,relatime
|-/var/lib/docker                                            /dev/sda2[/var/lib/sysbox/docker/080fb5dbe347a947accf7ba27a545ce11d937f02f02ec0059535cfc065d04ea0]        ext4     rw,relatime
|-/var/lib/kubelet                                           /dev/sda2[/var/lib/sysbox/kubelet/080fb5dbe347a947accf7ba27a545ce11d937f02f02ec0059535cfc065d04ea0]       ext4     rw,relatime
|-/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs /dev/sda2[/var/lib/sysbox/containerd/080fb5dbe347a947accf7ba27a545ce11d937f02f02ec0059535cfc065d04ea0]    ext4     rw,relatime
|-/usr/src/linux-headers-5.4.0-65                            /usr/src/linux-headers-5.4.0-65                                                                           shiftfs  ro,relatime
|-/usr/src/linux-headers-5.4.0-65-generic                    /usr/src/linux-headers-5.4.0-65-generic                                                                   shiftfs  ro,relatime
`-/usr/lib/modules/5.4.0-65-generic                          /lib/modules/5.4.0-65-generic                                                                             shiftfs  ro,relatime
```

All of these mounts are considered special / immutable because they are setup
during container creation time (i.e., before any process inside the
container starts executing).

In order to ensure proper isolation between the container and the host, Sysbox
places restrictions on what mount, remount, and unmount operations the processes
inside the container can do with these immutable mounts.

The default restrictions are:

Remounts:

-   A read-only immutable mount can't be modified (i.e., remounted) as a
    read-write mount.

    -   This ensures read-only mounts setup at container creation time remain as
        such.

    -   This behavior can be changed by setting the sysbox-fs config option
        `allow-immutable-remounts=true`.

    -   Note that the opposite does not apply: a read-write immutable mount **can** be
        modified to a read-only mount, since this creates a stronger restriction on
        the mount.

-   Other attributes of immutable mounts can't be changed via a remount
    (e.g., nosuid, noexec, relatime, etc.)

Unmounts:

-   The filesystem root "/" can't be unmounted.

-   The immutable mounts at /proc and /sys (as well as any submounts underneath
    them) can't be unmounted.

-   Other immutable mounts *can* be unmounted. Doing so exposes the contents
    of the container's immutable image below it.

    -   While it may surprise you that Sysbox allows these unmounts, this is
        necessary because system container images often have a process manager
        inside, and some process managers (in particular systemd) unmount all
        mountpoints inside the container during container stop. If Sysbox where to
        restrict these unmounts, the process manager will report errors during
        container stop

    -   Allowing unmounts of immutable mounts is typically not a security
        concern, because the unmount normally exposes the underlying contents of
        the system container's image, and this image will likely not have
        sensitive data that is masked by the mounts.

    -   Having said this, this behavior can be changed by setting the sysbox-fs
        config option `allow-immutable-unmounts=false`. When this option is set,
        Sysbox does restrict unmounts on all immutable mounts.

    -   See the [quickstart guide](../quickstart/security.md#immutable-mountpoints--v030-)
        for an example.

Restricted mount operations typically fail with "EPERM". For example,
continuing with the prior example, let's try to remount as read-write
the `myvol` mount:

```console
root@syscont:/# mount -o remount,rw,bind /mnt/myvol
mount: /mnt/myvol: permission denied.
```

The same behavior occurs with the immutable read-only mount of the host's linux
headers, setup implicitly by Sysbox into the container:

```console
root@syscont# mount -o remount,rw,bind /root/linux-headers-5.4.0-6
mount: /root/linux-headers-5.4.0-6: permission denied.
```

In the example above, even though the root user had full capabilities inside
the system container, it got EPERM when it tried to remount the immutable
mounts because Sysbox detected the operation and blocked it.

Note that these restrictions apply whether the mount occurs inside the Linux
mount namespace for the system container, or any other mount namespace created
inside the container (e.g., via `unshare -m`).

### Bind-Mounts from Immutable Mounts

Bind-mounts from immutable mounts are also restricted, meaning that it's OK to
create a bind-mount from an immutable mount to another mountpoint inside the
system container, but the new mountpoint will have similar restrictions as
the corresponding immutable mount.

The restrictions for bind mounts whose source is an immutable mount are:

Remount:

-   A bind mount whose source is a read-only immutable mount can't be modified
    (i.e., remounted) as a read-write mount.

    -   This ensures read-only mounts setup at container creation time remain as
        such.

    -   This behavior can be changed by setting the sysbox-fs config option
        `allow-immutable-remounts=true`.

Unmount:

-   No restrictions.

Continuing with the prior example, inside the system container let's create a
bind mount from the immutable read-only mount `/usr/src/linux-headers-5.4.0-65` to
`/root/headers`, and attempt a remount on the latter:

```console
root@syscont:/# mkdir /root/headers

root@syscont:/# mount --bind /usr/src/linux-headers-5.4.0-65 /root/headers

root@syscont:/# mount -o remount,bind,rw /root/headers
mount: /root/headers: permission denied.
```

As you can see, the operation failed with EPERM (as expected) because the
original mount `/usr/src/linux-headers-5.4.0-65` is a read-only immutable mount.

Note that the new bind-mount can be unmounted without problem. Sysbox places
no restriction on this since this simply removes the bind mount without
having any effect on the immutable mount.

```console
root@syscont:/# umount /root/headers
```

### Other Mounts, Remounts, Unmounts are Allowed

Except for the restrictions listed above, other mounts, remounts, and unmounts work
fine inside the system container (just as they would on a physical host or VM).

For example, one can create a new tmpfs mount inside, remount it read-only, and
unmount it without problem. The new mount can even be stacked on top of an
immutable mount, in which case it simply "hides" the immutable mount underneath
(but does not change or remove it, meaning that container isolation remains
untouched).

### Inner Container Mounts

When launching containers inside a system container (e.g., by installing Docker
inside the system container), the inner container manager (e.g., Docker) will
setup several mounts for the inner containers.

This works perfectly fine, as those mounts typically fall under the "other
mounts" category described in the prior section. However, if any of those mounts
is associated with an immutable mount of the outer system container, then the
immutable mount restrictions above apply.

For example, let's launch a system container that comes with Docker inside. We
will mount as "read-only" a host volume `myvol` into the system container's
`/mnt/myvol` directory:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname=syscont -v myvol:/mnt/myvol:ro nestybox/alpine-docker
```

Inside the system container, let's start Docker:

```console
/ # dockerd > /var/log/dockerd.log 2>&1 &
```

Now let's launch an inner privileged container, and mount the system container's
`/mnt/myvol` mount (which is immutable since it was setup at system container
creation time) into the inner container:

```console
/ # docker run -it --rm --privileged --hostname=inner -v /mnt/myvol:/mnt/myvol ubuntu
```

Inside the inner privileged container, we can use the mount command. Let's try
to remount `/mnt/myvol` to read-write:

```console
root@inner:/# mount -o remount,rw,bind /mnt/myvol
mount: /mnt/myvol: permission denied.
```

As expected, this failed because the inner container's `/mnt/myvol` is
technically a bind-mount of `/mnt/myvol` in the system container, and the latter
is an immutable read-only mount of the system container, so it can't be
remounted read-write.

For the reasons described above, initial mount immutability is a key security
feature of Sysbox. It enables system container processes to be properly
isolated from the host, while still giving these processes full access to
perform other types of mounts, remounts, and unmounts inside the container.

As a point of comparison, other container runtimes either restrict mounts
completely (by blocking the `mount` and `umount` system calls via the Linux
seccomp mechanism) which prevents several system-level programs from working
properly inside the container, or alternatively allow all mount, remount, and
unmount operations inside the container (e.g., as in Docker privileged
containers), creating a security weakness that can be easily used to break
container isolation.

In contrast, Sysbox offers a more nuanced approach, in which the `mount` and
`umount` system calls are allowed inside the container, but are restricted
when applied to the container's initial mounts.

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

The score is in the range \[-1000:1000], where higher values means higher
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
value in the range \[-999:1000], via `/proc/[pid]/oom_score_adj`.

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
