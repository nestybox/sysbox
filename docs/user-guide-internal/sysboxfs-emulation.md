# Sysbox Internal User Guide: Procfs and Sysfs Emulation

## Contents

-   [Introduction](#introduction)
-   [Procfs Background](#procfs-background)
-   [Sysfs Background](#sysfs-background)
-   [Procfs / Sysfs in System Containers](#procfs--sysfs-in-system-containers)
-   [Procfs / Sysfs inside a Sys Container](#procfs--sysfs-inside-a-sys-container)
-   [Procfs / Sysfs Emulation](#procfs--sysfs-emulation)
-   [Intercepting Procfs / Sysfs Mounts Inside a Sys Container](#intercepting-procfs--sysfs-mounts-inside-a-sys-container)
-   [Intercepting Procfs / Sysfs Unmounts Inside a Sys Container](#intercepting-procfs--sysfs-unmounts-inside-a-sys-container)

## Introduction

Sysbox-fs' emulation capabilities are a fundamental component of Sysbox
runtime. These ones complement sysbox-runc features to offer a more
complete 'virtual-host' abstraction.

As of today, sysbox-fs supports the (partial) emulation of the
following components:

-   procfs emulation
-   sysfs emulation
-   syscall emulation

This document spells out the details of how this emulation process is
carried out.

## Procfs Background

-   The Linux procfs is a pseudo-filesystem that provides a user-space
    interface into control and status information associated with kernel
    resources. It's typically (but not necessarily) mounted at `/proc`
    within a host or inside a container.

-   When a process mounts procfs, the process' namespace membership
    determines the procfs resources exposed by the kernel to the
    process as described below.

-   Many kernel resources exposed via procfs are "namespaced", meaning
    that its possible for a group of processes to get an isolated view
    of the resource. For example:

    -   The procfs pid directories (e.g., `/proc/<pid>)` vary depending
        on the pid namespace of the process reading procfs.

    -   The network control/status under `/proc/sys/net` vary depending
        on the net namespace of the process reading procfs.

-   Some kernel resources exposed via procfs are not namespaced, meaning
    that the view of the resource is global to all processes, regardless
    of the namespaces they are in.

    -   Resources are not namespaced either because:

        -   They are global kernel resources whose namespacing does not make
            sense. E.g.,

            -   `/proc/buddyinfo`
            -   `/proc/interrupts`
            -   `/proc/sys/kernel/*` (most controls here).
            -   And many others.

        -   They could conceptually be namespaced but haven't been yet.

            -   `/proc/cpuinfo`
            -   `/proc/meminfo`
            -   And several others.

-   In addition, some kernel resources are only exposed by procfs in the initial
    user namespace, but are hidden in child user namespaces.

    -   For example, several resources under `/proc/sys/net`, such as:

        `/proc/sys/net/netfilter/nf_conntrack_acct`
        `/proc/sys/net/netfilter/nf_conntrack_buckets`
        `/proc/sys/net/ipv6/route/gc_*`

        See [here](https://github.com/torvalds/linux/commit/464dc801c76aa0db88e16e8f5f47c6879858b9b2#diff-82c14a1d494f0048fdf74ec6b07b5d4b)
        for the related kernel commit.

## Sysfs Background

As in procfs case, the sysfs filesystem is also a pseudo-filesystem
that provides an interface to kernel data structures.

Most of the items previously covered in procfs introduction also apply
here. There are subtle differences in the approach followed to expose
certain sysfs resources, but in essence, both procfs and sysfs
emulation serve the main purpose.

## Procfs / Sysfs in System Containers

-   In order for a sys container to emulate a virtual host and be
    capable of running system level software, Sysbox emulates portions
    of procfs and sysfs inside a sys container.

-   The purpose of this emulation is to:

    -   Expose and emulate namespacing of kernel resources that are not yet
        namespaced by the Linux kernel (but can conceptually be namespaced).

    -   Expose kernel resources that are normally only shown in the initial
        user namespace (and not within child user namespaces).

    -   Expose system-wide kernel resources that are statically defined and
        not bound to change (performance purposes).

-   This allows Sysbox to offer a more complete and efficient pseudo-file
    systems within system containers, thereby improving the abstraction of a
    "virtual host" presented to processes inside said containers.

## Procfs / Sysfs inside a Sys Container

-   When a sys container starts, Sysbox always mounts the emulated
    procfs and sysfs resources at `/proc` and `/sys` respectively.

    -   This is done through coordination between sysbox-runc and
        sysbox-fs at sys container creation time.

-   In addition, a process inside a sys container is allowed to mount
    procfs / sysfs at any time and at any location within the system
    container.

-   Mounting procfs / sysfs  within the sys container is not uncommon.
    For example, it occurs every time an inner container is launched
    within the sys container.

-   To handle this, Sysbox traps mount syscalls issued by processes
    inside the sys container, and if the mount type specifies a procfs
    or a sysfs mount, Sysbox ensures the mounted file-system is
    partially emulated by Sysbox-fs (just as `/proc` / `/sys` inside
    the sys container is).

    -   Syscall trapping is done using the Linux kernel's seccomp-bpf
        notification mechanism.

    -   See section [Intercepting Procfs / Sysfs Mounts Inside A Sys Container](#intercepting-procfs--sysfs-mounts-inside-a-sys-container)
        for more info on this.

## Procfs / Sysfs Emulation

-   Sysbox does procfs / sysfs emulation by using a "hybrid" approach
    that mounts the Linux kernel's procfs / sysfs at the desired
    mountpoint and then mounts the fuse-based sysbox-fs on top of
    portions of the underlying pseudo file-system (e.g., `/proc/sys`,
    `/proc/uptime`, etc.)

-   This hybrid approach allows Sysbox to only emulate portions of
    procfs / sysfs as needed (e.g., emulate namespacing of kernel
    resources that are not namespaced, or expose kernel resources only
    shown in the initial user namespace).

-   For example, when a process within a sys container accesses
    `/proc/<pid>`, that access is serviced by the procfs in the Linux
    kernel. However, if a process within a sys container accesses
    `/proc/uptime`, that access is serviced by sysbox-fs.

-   The list of which portions of procfs / sysfs are emulated by
    sysbox-fs is a work-in-progress and expected to change as we add
    more functionality to Sysbox or due to new changes in the Linux
    kernel.

-   However, the emulated procfs / sysfs mount for a sys container has
    the following characteristics:

    -   Accesses to procfs / sysfs resources that are namespaced by the
        Linux kernel are serviced by the kernel's procfs / sysfs.

    -   Accesses to procfs / sysfs resources emulated by sysbox are
        serviced by sysbox-fs. These fall into one of the following
        categories:

        -   Resources whose namespacing is emulated by sysbox-fs (i.e.,
            resources not namespaced by the Linux kernel).

        -   Resources only exposed in the initial user namespace.

        -   Frequently accessed resources holding system-wide and static
            information (performance purposes).

    -   All other accesses are serviced by the kernel's procfs / sysfs
        (i.e., accesses to procfs / sysfs resources that are not
        namespaced by the Linux kernel or emulated sysbox-fs).

### Permission Checks

-   When emulating procfs / sysfs, Sysbox ensures that the process
    doing an access to the pseudo-fs has the appropriate credentials
    and capabilities to perform the access.

    -   E.g., a non-root process with zero capabilities inside the sys
        container accessing a file under procfs with `0744` permissions
        may read but not write said file. A root process inside the sys
        container may read and write to said file.

-   For this purpose, Sysbox-fs heavily relies on the Linux Kernel's
    VFS component. This is accomplished by instructing FUSE's Kernel
    module to operate on ['default-permissions'](http://man7.org/linux/man-pages/man8/mount.fuse.8.html) mode.

### Procfs / Sysfs Emulation in Inner Containers

-   Within a sys container, it's possible to launch inner containers.

-   For each inner container, procfs / sysfs will be typically mounted
    at the inner container's `/proc` / `/sys` directory.

-   As mentioned above, Sysbox traps the mount syscall issued by
    processes inside a sys container, and if it's a new procfs or sysfs
    mount, it sets up a new mount of the emulated procfs / sysfs. It
    does this as follows:

    -   The kernel's procfs / sysfs is mounted within the container; since
        the mount occurs within the context of the inner container's
        namespaces, the kernel will know what resources to expose to the
        inner container.

    -   The portions of procfs / sysfs emulated by Sysbox are also mounted
        within the inner container (e.g., at the inner container's
        `/proc/sys`, `/proc/uptime`, etc.). The manner in which this is
        done is explained later in this doc.

-   The emulated procfs / sysfs mount for an inner container has the
    following characteristics:

    -   Accesses to procfs / sysfs resources that are namespaced by the
        Linux kernel are serviced by the kernel's procfs / sysfs.

    -   Accesses to procfs / sysfs resources emulated by sysbox in the
        parent sys container are serviced by sysbox-fs. For example:

        -   `/proc/uptime` within the inner container is the same as the
            `/proc/uptime` of the parent sys container.

        -   `/proc/sys/net/netfilter/nf_conntrack_max` within the inner
            container is the same as the corresponding file in the parent
            sys container.

    -   All other accesses are serviced by the kernel's procfs / sysfs
        (i.e., accesses to procfs / sysfs resources that are not namespaced
        by the Linux kernel or emulated sysbox-fs in the parent sys
        container).

-   The above applies more generally to any procfs / sysfs mount done
    within a sys container, whether it be a procfs / sysfs mount for an
    inner container, or simply a redundant mount of procfs / sysfs at
    some arbitrary directory within the sys container.

    -   For example, if a process within a sys container mounts procfs
        at `/root/proc`, all of the above-mentioned characteristics would
        apply to the newly created mount.

    -   Or if a process within a sys container enters a new net namespace
        and mounts procfs at `/root/proc`, the same applies as well.

### Emulation Details

Sysbox-fs emulates `proc/sys` and all the hierarchy beneath it. It does
this in order to gain full control over the contents of `proc/sys`,
including its sub-directories.

A similar approach, although to a much lesser extend, is applied for
`/sys` resources -- curently only `/sys/module/nf_conntrack/parameters/hashsize`,
node is being emulated.

For the `/proc/sys` case, the emulation is done as follows:

-   If the access is to a kernel resource under `proc/sys` that is
    emulated by sysbox-fs, sysbox-fs performs the emulation action.

    E.g., `/proc/sys/net/netfilter/nf_conntrack_max`

-   Otherwise, sysbox-fs does a "passthrough" of the access to the
    kernel's procfs. It does this by dispatching a child process that
    enters the namespaces of the process performing the access (except
    the mount namespace) and performs the corresponding access on the
    host's /proc/sys.

    -   The reason the sysbox-fs handler does not enter the mount
        namespace is because it wants to access the host's /proc/sys.
        Had it entered the mount namespace, it would be accessing the
        sysbox-backed /proc/sys (creating a recursive access). Even
        though the process accesses the host /proc/sys, by virtue of
        doing so from within the process namespaces (e.g., user, net, etc),
        it accesses procfs data associated with those namespaces.

    -   By virtue of entering the user-ns, the child process gains
        full capabilities within the user-ns (see user_namespaces(7)).

    -   Note that the namespaces of the process performing the access may
        not be the same namespaces associated with the sys container. For
        example, if the process performing the access is inside an inner
        container, then its namespaces are those of the inner container,
        not those of the sys container.

## Intercepting Procfs / Sysfs Mounts Inside a Sys Container

This section describes the rationale and mechanism used by sysbox to
handle procfs / sysfs mounts done by processes inside the sys container.

This does not include the initial mount of procfs and sysfs at the sys
container's `/proc` and `/sys` directories, which is setup via
coordination between sysbox-runc and sysbox-fs at sys container creation
time, before the container's init process runs.

### Rationale

The rationale for trapping and emulating procfs / sysfs mounts inside
the sys container is simple: all mounts of procfs / syfs inside the sys
container must present a consistent view of the system.

For example, when a sys container is created, sysbox-runc mounts a
partially emulated procfs under `/proc`. If a user creates a procfs
mount at another directory (e.g., `/root/proc`), she should see the
partially emulated procfs there too. An equivalent behavior is expected
for sysfs file-system.

### Mount Syscall Trapping Mechanism

Sysbox uses the Linux kernel's seccomp-bpf notification mechanism to
setup trapping for mount syscalls issued by processes inside the sys
container. This setup is done at sys container creation time, in
coordination between sysbox-runc and sysbox-fs.

Once the sys container is running, when a process inside a sys
container issues the `mount` syscall, sysbox-fs is notified of the
event and receives the syscall information before the Linux kernel has
a chance to process it.

Sysbox-fs then makes a decision on whether to emulate the mount
syscall or not.

In the case where the syscall is emulated, sysbox-fs does the
emulation action and responds to the kernel indicating that it should
not process the mount syscall any further but instead return a value
to the process that invoked it.

In the case where the syscall is not emulated, sysbox-fs responds to
the kernel indicating that it should process the mount syscall as
usual.

### Mount Syscall Emulation

Sysbox-fs only emulates mount syscalls that do the following inside the
sys container:

1) Create a new procfs or sysfs mountpoint.
2) Create a bind mount from a procfs or sysfs mountpoint.
3) Perform a remount over a procfs or sysfs mountpoint.

The handling for each of these is described below.

Mount syscalls that mount other filesystem types, create other bind
mounts, or perform other remount operations do not require emulation
by Sysbox-fs; those are simply passed backed to the Linux kernel.

See section [Intercepting Procfs / Sysfs Unmounts Inside a Sys Container](#intercepting-procfs--sysfs-unmounts-inside-a-sys-container)
for cases where sysbox-fs traps and emulates unmount syscalls.

#### Identifying the procfs / sysfs mount type

To identify the procfs / sysfs mount type (new, bind, or remount),
Sysbox must perform a check on the mount syscall's `filesystemtype`
and `mountflags` as follows:

-   New procfs mounts:

    -   The `filesystemtype` must indicate "proc" or "sysfs".

    -   The following `mountflags` must not be set:

        `MS_REMOUNT`, `MS_BIND`, `MS_SHARED`, `MS_PRIVATE`, `MS_SLAVE`, `MS_UNBINDABLE`, `MS_MOVE`.

-   Remounts:

    -   The `mountflags` has `MS_REMOUNT` set.

-   Bind mounts:

    -   The `mountflags` has `MS_BIND` set and `MS_REMOUNT` cleared.

See mount(2) for details.

#### New Procfs / Sysfs Mounts

For mount syscalls that setup new procfs / sysfs mountpoints inside
the sys container, Sysbox should _ideally_ perform the following
actions:

-   Mount the kernel's procfs / sysfs at the target path

    -   We call this the "base mount".

-   Setup additional sysbox-fs mounts on top of it, just as sysbox does
    on the sys container's `/proc` and `/sys`. In other words, Sysbox
    would bind mount `/var/lib/sysboxfs/cntr-id` to the `proc/sys`,
    `proc/uptime`, etc. at the target procfs / sysfs mountpoint.

    -   We call these the "submounts".

That is, Sysbox would perform actions equivalent to:

```console
    mount -t proc proc <target-mountpoint>
    mount --bind /var/lib/sysboxfs/cntr-id/proc/sys <target-mountpoint>/sys
    mount --bind /var/lib/sysboxfs/cntr-id/proc/uptime <target-mountpoint>/uptime
    mount --bind /var/lib/sysboxfs/cntr-id/proc/swaps  <target-mountpoint>/swaps
    ...
```

Note that in order for sysbox to do this, it needs to enter the sys
container's mount namespace yet have access to the host's root
directory (where `/var/lib/sysboxfs/cntr-id` lives). But this is not
trivial for two reasons:

1) When the sysbox process enters the sys container's mount-ns via
`setns(2)`, the kernel does an implicit `chroot` into the sys
container's root directory. Thus, the sysbox process no longer has
access to `/var/lib/sysbox/cntr-id` and is not able to perform the
mount.

Overcoming this requires that sysbox spawns a process that enters the
sys container mount namespace before the sys container's init process
does it's pivot root. This way, sysbox can enter the mount namespace
of said process and perform the bind mount of `/var/lib/sysbox/cntr-id`
into the target mountpoint inside the sys container.

2) It requires that sysbox-fs track multiple mount points. In other
words, sysbox-fs would need to understand that for a given sys
container, there are multiple mount points of procfs backed by
sysbox-fs and handle the accesses appropriately.

An alternative solution that avoids the challenges associated with
mounting `/var/lib/sysboxfs/cntr-id` inside the sys container is to
instead bind mount the sysbox-fs backed portions of the sys
container's `/proc` / `/sys` over the new procfs / sysfs mountpoints.

Something equivalent to this command sequence within the sys
container:

```console
    mount -t proc proc <target-mountpoint>
    mount --bind /proc/sys <target-mountpoint>/sys
    mount --bind /proc/uptime <target-mountpoint>/uptime
    mount --bind /proc/swaps <target-mountpoint>/swaps
    mount -t sys sysfs <target-mountpoint>
    mount --bind /sys/module/nf_conntrack/parameters/hashsize <target-mountpoint>/module/nf_conntrack/parameters/hashsize`
```

Pros of this solution:

-   Avoids the problem of mounting `/var/lib/sysbox/cntr-id` described
    previously.

-   Supports independent mount flags (e.g., read-only) per procfs /
    sysfs mountpoint inside the sys container.

-   Supports independent mount options (e.g., hidepid) per procfs /
    sysfs mountpoint inside the sys container.

-   Ensures that multiple mounts of procfs / sysfs within the sys
    container are identical.

Cons of this solution:

-   Creates an implicit dependency between all procfs / sysfs mounts
    inside the sys container and the `/proc` / `/sys` mounts inside
    the sys container. For example, a procfs mount at
    `<target-mountpoint>/sys` depends on `/proc/sys` (because the
    latter is bind mounted on the former). This is not ideal, but
    will likely not matter in practice.

NOTE: We decided to go with this alternative solution as it's simpler
to implement and has no mayor drawbacks. But see sysbox issue #590
for some limitations around it.

#### Bind Mounts from Procfs / Sysfs

For mount syscalls that create bind mounts from /proc or /sys inside
the container, sysbox-fs processes these by recursively mounting the
base mount (e.g., /proc) and submounts (e.g., /proc/sys, /proc/uptime,
etc.) at the bind-mount target.

Bind mount operations are common when launching inner containers (i.e., the
inner runc creates bind mounts over the procfs mounts that it creates for
the inner container).

#### Bind-to-self Mounts over Procfs / Sysfs Submounts

For mount syscalls that do bind-to-self mounts over a procfs or sysfs
submount (e.g., `mount --bind /root/proc/sys /root/proc/sys`),
sysbox-fs only does path resolution and permission checking, but
otherwise takes no action.

That is, if the path resolution and permission checking steps pass,
then sysbox-fs tells the kernel to return back to the caller of the
syscall with a successful status.

We call such bind mounts "superficial".

The rationale for this is:

-   Typically, self-referencing bind-mounts over portions of procfs (or
    sysfs) are done in preparation to performing a remount that modifies
    some attribute of the mount (e.g., some process in the sys container
    mounts procfs as read-write in `/root/proc` and then sets up a
    self-referencing bind-mount on `/root/proc/sys` in preparation to
    make `/root/proc/sys` readonly). Within the sys container however,
    portions of procfs backed by sysbox-fs are already bind-mounts
    (e.g., `/root/proc/sys` is already a bind mount backed by
    sysbox-fs). Thus skipping the bind mount won't have negative effects
    on a subsequent remount.

-   If we were to honor the superficial bind-mount, then we must also
    honor a corresponding unmount. But this becomes tricky because we
    also want to ensure a process inside the sys container can't unmount
    portions of procfs (or sysfs) backed by sysbox-fs. We would therefore
    need some way of differentiating between an umount that is trying to
    remove portions of procfs backed by sysbox-fs from a unmount that is
    trying to remove a superficial bind-mount. This requires some sort of
    reference counting in sysbox-fs for each procfs mountpoint, which is
    "do-able" but a bit complex.

-   If we were to honor the superficial bind-mount, it would create a
    bind-mount over the existing bind-mount for these files/directories
    (as set during a new procfs mount as described in the prior
    section). This is fine but looks a bit strange.

By not taking any real action on the superficial bind-mount or a
corresponding unmount, we provide a simple solution to the problem.

The caveat is that a user that does superficial bind mounts over
procfs / sysfs portions backed by sysbox-fs will not see them take
effect (they won't be stacked as he/she may expect).

NOTE: In the future we could improve the solution by doing reference
counting as described above.

#### Remounts Over Procfs / Sysfs Portions Backed by Sysbox-fs

For mount syscalls that do a remount of a base mount (e.g., `mount -o
remount,ro /proc`), Sysbox extends the remount to the submounts. The
rationale for this is that the base mount and submounts form logically
a single procfs (or sysfs) mount, and therefore a remount of the base
mount extends to the submounts.

For mount syscalls that do a remout of a submount (e.g., `mount -o
remount,ro /proc/sys`), Sysbox performs the remount on the target
submount only.

When doing a remount of a base mount or submount, Sysbox ensures that
the existing flags and filesystem-specific options associated with the
mountpoint are kept unchanged, except of course for the flags being
explicitly changed by the remount operation.

Remount operations are common when launching inner containers (i.e., the
inner runc performs remounts over the procfs mounts that it creates for
the inner container).

#### Identifying procfs / sysfs mounts backed by sysbox-fs

When handling bind mounts and remounts, sysbox-fs identifies if a
mountpoint is backed by sysbox-fs by searching the mountpoint path in
the `/proc/[pid]/mountinfo` file (where `[pid]` corresponds to the
process that made the mount syscall).

#### Path resolution

Sysbox must perform path resolution on the mount's target path, as
described in path_resolution(7). That is, it must be able to resolve
paths that are absolute or relative, and those containing ".", "..",
and symlinks within them.

NOTE: the target mount path is relative to current-working-dir and
root-dir associated with the process performing the mount. The latter
may not necessarily match the sys container's root-dir. Sysbox must
resolve the path accordingly.

#### Permission checks

Sysbox must perform permission checking to ensure the process inside
the sys container that is performing the procfs / sysfs mount operation
has appropriate privileges to do so. The rules are:

-   The mounting process must have `CAP_SYS_ADMIN` capability (mounts
    are not allowed otherwise).

-   In addition, the mounting process must have search permission on the
    the path from it's current working directory to the target
    directory, or otherwise have `CAP_DAC_READ_SEARCH` and
    `CAP_DAC_OVERRIDE`. See path_resolution(7) for details.

#### Mount Flags

The `mount` syscall takes a number of `mountflags` that specify
attributes such as read-only mounts, no-exec, access time handling,
etc. Some of those apply to procfs mounts, most do not.

When handling new procfs / sysfs mounts, sysbox-fs simply passes the
given mount flags to the Linux kernel when mounting procfs / sysfs.

When handling remounts over portions of procfs / sysfs backed by
sysbox-fs, the flags are handled as described in section
[Remounts Over Procfs / Sysfs Portions Backed by Sysbox-fs](#remounts-over-procfs--sysfs-portions-backed-by-sysbox-fs)
above.

#### Mount options

Per procfs(5), procfs mounts take two mount options: `hidepid` and
`gid`.

These can be set independently for each procfs mountpoint. Ideally,
Sysbox would honor these mount options when procfs is mounted within
the sys container.

Note that these are typically set as follows:

```console
    / # mount -t proc proc /tmp/proc
    / # mount -o remount,hidepid=2 /tmp/proc
```

And result in two `mount` syscalls such as:

```
syscallNum =  165, type = proc, src = proc, target = /tmp/proc, flags = 8000, data =
syscallNum =  165, type = proc, src = proc, target = /tmp/proc, flags = 208020, data = hidepid=2
```

Notice that the second syscall uses the `flags` to specify a remount
operations, and passes the `hidepid` option via the `data`.

#### Read-only and masked paths

A sys container typically has some paths under `/proc` configured as
read-only or masked.

For example, when launched with Docker, we see `/proc/keys`,
`/proc/timer_list` are masked by bind-mounting the `/dev/null` device
on top of them. Similarly, `/proc/bus`, `/proc/fs` and others are
configured as read-only.

For consistency between procfs mounted by at the sys conatiner's
`/proc` and procfs mounted in other mountpoints inside the sys
container, the same masked paths and read-only paths must be honored
in the other mountpoints.

#### Mount Syscall Emulation Steps

Based on the prior sections, Sysbox follows the following steps when
trapping a mount syscall:

-   Perform path resolution & permission checking on the mount syscall
    paths.

-   If the syscall indicates

    -   A new procfs / sysfs mount:

        -   Emulate as described below

    -   Bind-mount or remount on a sysbox-fs base mount or submount:

        -   Emulate as described below

    -   Other:

        -   Tell the kernel to process the mount syscall; no further action
            is necessary.

-   Enter the required namespaces of the process that made the mount syscall

    -   Note that this results in an implicit chroot into the process'
        root-dir.

    -   Note that when doing a new procfs or sysfs mount, we must enter
        the user-ns of the target process because otherwise the procfs /
        sysfs mount would be done from within the sysbox-fs user-ns (i.e.,
        the host's init user-ns), and this causes an inconsistency: in
        Linux, mounts done from a init user-ns have different resources
        exposed to them than mounts done from a non-init user-ns.

-   For new procfs / sysfs mounts:

    -   Mount / Sysfs procfs at the target mountpoint (i.e., the base mount).

        -   Pass in the appropriate flags (e.g., MS_RDONLY) and options (e.g., hidepid)
            that are present in the trapped mount syscall.

    -   Create the sysbox-fs submounts.

        -   Note: the submounts must honor the MS_RDONLY flag when present
            in the mount syscall.

    -   If this operation fails, return the corresponding error.

    -   Return success on the mount syscall.

-   For remounts

    -   If the remount is on the base mount, extend it to the submounts too.

    -   If the remount is on a submount, apply it only on that submount.

    -   Merge the existing mount flags with the remount flags as described in
        [Remounts Over Procfs / Sysfs Portions Backed by Sysbox-fs](#remounts-over-procfs--sysfs-portions-backed-by-sysbox-fs).

    -   Return success on the mount syscall.

-   For bind-mounts

    -   Ignore bind-to-self mounts on sysbox-fs submounts.

    -   If the bind-mount source is a base mount, do a recursive mount of the submounts too.

    -   If the bind-mount source is a submount, just bind mount that submount

-   NOTE: It's important that the process invoking the syscall does not
    notice any difference between how sysbox handles the syscall and how
    the Linux kernel would handle it.

-   NOTE: for errors that occur during the emulation of the procfs /
    sysfs mount, we handle them as follows:

    -   If the error occurs during process privilege checks, return EPERM.

    -   If the error occurs during path resolution, return the appropriate
        error (e.g., EACCES, ELOOP, ENAMETOOLONG, etc.)

    -   If the error is caused when mounting the kernel's procfs / sysfs,
        return the corresponding error.

    -   Otherwise return EINVAL or EBUSY as appropriate.

-   NOTE: the mount syscall emulation must ensure atomicity: if a step fails,
    any actions visible to the process that called the mount syscall must
    be reverted before the mount syscall returns. For example, if one of
    the sysbox-fs bind mounts fails, any prior mounts must be reverted.

## Intercepting Procfs / Sysfs Unmounts Inside a Sys Container

In addition to procfs / sysfs mounts, Sysbox also traps and emulates
procfs / sysfs unmount operations.

The purpose of this is the following:

1) Prevent a user from unmounting the procfs and sysfs mounts at /proc
   and /sys inside a container.

2) Prevent a user from unmounting submounts of procfs or sysfs
   mounts.

3) If a user creates a procfs mount in some directory inside the sys
   container (which causes sysbox-fs to setup the base mount and
   submounts), an unmount of procfs should remove the base mount and
   submounts.

Bullets (1) and (2) are needed as otherwise a user inside a sys
container would be able to unmount the portions of procfs / sysfs
emulated by sysbox-fs and thus expose the kernel's real procfs / sysfs
inside the sys container. Allowing this would be both a functional and
security problem.

From a functional perspective, it would mean that the sys container
won't work as expected (e.g., reading `/proc/uptime` would return the
host uptime instead of the sys container's uptime, accessing
`/proc/sys/net/netfilter/nf_conntrack_max` would not be possible, etc.)

From a security perspective, it would mean that a process inside the
sys container would be able to obtain information about the host via
`/proc` that would normally be hidden inside the sys container.

Bullet (3) is needed because a root user inside the sys container is
allowed to unmount procfs / sysfs just as a root user in a real host
would be.

In order to support this, Sysbox must trap and emulate the unmount
procfs / sysfs syscall, and perform the unmount of the sys container's
procfs / sysfs by first unmounting the submounts and then the base
mount as follows:

```console
umount <target-mountpoint>/swaps
umount <target-mountpoint>/uptime
umount <target-mountpoint>/sys
umount <target-mountpoint>
```

### umount2 syscall

Linux currently supports one syscall to perform unmounts: `umount2`.
Previously, `umount` syscall was also supported, but that's not the
case as of recent kernels.

`unmount2` takes a `flags` argument to control the behavior of the
 unmount operation (e.g., `MNT_FORCE`, `MNT_DETACH`, `MNT_EXPIRE`, and
 `UMOUNT_NOFOLLOW`).

Sysbox-fs honors the `flags` arguments by performing the corresponding
unmounts using the same flags.

Note that the `UMOUNT_NOFOLLOW` flag requires that the `umount2`
syscall does not dereference the unmount target if it's a symbolic
link.

### Unmount Syscall Emulation Steps

-   Do path resolution & permission checking

    -   If path resolution fails, return an appropriate error.

    -   NOTE: if the incoming syscall request has the flag `UMOUNT_NOFOLLOW`,
        then path resolution must not dereference the target mountpoint if it's
        a symlink.

-   If the syscall is an unmount on /proc or /sys, Sysbox does not allow
    this (returns EBUSY).

-   If the syscall is an unmount on a sysbox-fs submount, Sysbox ignore
    the unmount (needed as Sysbox also ignores bind-to-self mounts on
    submounts).

    -   This ensures that users can't unmount portions of procfs / sysfs
        backed by sysbox-fs.

-   Otherwise, if the syscall is an unmount of a Sysbox-fs procfs or sysfs base mount,
    enter appropriate namespaces of the process that made the unmount syscall
    and perform the unmount of the submounts first, then of the base mount.

        umount <target-mountpoint>/swaps
        umount <target-mountpoint>/uptime
        umount <target-mountpoint>

    -   Execute the above mounts using the same flags that the trapped syscall
        uses (e.g., `MNT_DETACH`, etc).

    -   Return success on the syscall or failure if any of the above steps
        fails.

-   NOTE: It's important that the process invoking the syscall does not notice
    any difference between how sysbox handles the syscall and how the Linux
    kernel would handle it.

-   NOTE: for errors that occur during the emulation of the procfs / sysfs
    unmount, we handle them as follows:

    -   If the error occurs during process privilege checks, return EPERM.

    -   If the error occurs during path resolution, return the appropriate
        error (e.g., EACCES, ELOOP, ENAMETOOLONG, etc.)

    -   If the error is caused when unmounting the kernel's procfs, return
        the corresponding error.

    -   Otherwise return EINVAL or EBUSY as appropriate.

-   NOTE: Ideally, the unmount syscall emulation should ensure atomicity:
    that is, if a step fails, any actions visible to the process that called
    the unmount syscall must be reverted before the unmount syscall returns.
    For example, if one of the sysbox-fs bind unmounts fails, any prior
    unmounts must be reverted. However, this feature has not been implemented
    yet due to its associated complexity in the umount case.
