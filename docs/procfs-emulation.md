Sysbox: Procfs Emulation
========================

## Procfs Background

* The Linux procfs is a pseudo-filesystem that provides a user-space
  interface into control and status information associated with kernel
  resources. It's typically (but not necessarily) mounted at `/proc`
  within a host or inside a container.

* When a process mounts procfs, the process' namespace membership
  determines the procfs resources exposed by the kernel to the
  process as described below.

* Many kernel resources exposed via procfs are "namespaced", meaning
  that its possible for a group of processes to get an isolated view
  of the resource. For example:

  - The procfs pid directories (e.g., `/proc/<pid>)` vary depending
    on the pid namespace of the process reading procfs.

  - The network control/status under `/proc/sys/net` vary depending
    on the net namespace of the process reading procfs.

* Some kernel resources exposed via procfs are not namespaced, meaning
  that the view of the resource is global to all processes, regardless
  of the namespaces they are in.

  - Resources are not namespaced either because:

    - They are global kernel resources whose namespacing does not make
      sense. E.g.,

      - `/proc/buddyinfo`
      - `/proc/interrupts`
      - `/proc/sys/kernel/*` (most controls here).
      - And many others.

    - They could conceptually be namespaced but haven't been yet.

      - `/proc/cpuinfo`
      - `/proc/meminfo`
      - And several others.

* In addition, some kernel resources are only exposed by procfs in the initial
  user namespace, but are hidden in child user namespaces.

  - For example, several resources under `/proc/sys/net`, such as:

    `/proc/sys/net/netfilter/nf_conntrack_acct`
    `/proc/sys/net/netfilter/nf_conntrack_buckets`
    `/proc/sys/net/ipv6/route/gc_*`

    See [here](https://github.com/torvalds/linux/commit/464dc801c76aa0db88e16e8f5f47c6879858b9b2#diff-82c14a1d494f0048fdf74ec6b07b5d4b)
    for the related kernel commit.

## Procfs in System Containers

* In order for a sys container to emulate a virtual host and be
  capable of running system level software, Sysbox emulates portions
  of procfs inside a sys container.

* The purpose of this emulation is to:

  - Expose and emulate namespacing of kernel resources that are not yet
    namespaced by the Linux kernel (but can conceptually be namespaced).

  - Expose kernel resources that are normally only shown in the initial
    user namespace (and not within child user namespaces).

* This allows Sysbox to present a more complete procfs within system
  containers, thereby improving the abstraction of a "virtual host"
  presented to processes inside said containers.

## Procfs Mounts inside a Sys Container

* When a sys container starts, Sysbox always mounts the emulated
  procfs at `/proc`.

  - This is done through coordination between sysbox-runc and
    sysbox-fs at sys container creation time.

* In addition, a process inside a sys container is allowed to mount
  procfs at any time and at any location within the system container.

* Mounting procfs within the sys container is not uncommon. For
  example, it occurs everytime an inner container is launched within
  the sys container.

* To handle this, Sysbox traps mount syscalls issued by processes
  inside the sys container, and if the mount specifies a new procfs
  mountpoint, Sysbox ensures the mounted procfs is partially
  emulated by Sysbox-fs (just as `/proc` inside the sys container is).

  - Syscall trapping is done using the Linux kernel's seccomp-bpf
    notification mechanism.

  - See section [Handling procfs Mounts Inside A Sys Container](#detecting-procfs-mounts-inside-a-sys-container) for
    more info on this.

## Procfs Emulation

* Sysbox does procfs emulation by using a "hybrid" approach that
  mounts the Linux kernel's procfs at the desired mountpoint and then
  mounts the fuse-based sysbox-fs on top of portions of procfs (e.g.,
  `/proc/sys`, `/proc/uptime`, etc.)

* This hybrid approach allows Sysbox to only emulate portions of
  procfs as needed (e.g., emulate namespacing of kernel resources
  that are not namespaced, or expose kernel resources only shown
  in the initial user namespace).

* For example, when a process within a sys container accesses `/proc/<pid>`,
  that access is serviced by the procfs in the Linux kernel. However,
  if a process within a sys container accesses `/proc/uptime`, that
  access is serviced by sysbox-fs.

* The list of which portions of procfs are emulated by sysbox-fs is a
  work-in-progress and expected to change as we add more functionality
  to Sysbox or due to new changes in the Linux kernel.

* However, the emulated procfs mount for a sys container has the
  following characteristics:

  - Accesses to procfs resources that are namespaced by the Linux
    kernel are serviced by the kernel's procfs.

  - Accesses to procfs resources emulated by sysbox are serviced by
    sysbox-fs. These fall into one of the following categories:

    - Resources whose namespacing is emulated by sysbox-fs (i.e.,
      resources not namespaced by the Linux kernel).

    - Resources only exposed in the initial user namespace.

  - All other accesses are serviced by the kernel's procfs (i.e.,
    accesses to procfs resources that are not namespaced by the Linux
    kernel or emulated sysbox-fs).

### Permission Checks

* When emulating procfs, Sysbox ensures that the process doing an
  access to procfs has the appropriate credentials and capabilities to
  perform the access.

  - E.g., a non-root process with zero capabilities inside the sys
    container accessing a file under procfs with `0744` permissions
    may read but not write said file. A root process inside the sys
    conatainer may read and write to said file.

### Procfs Emulation in Inner Containers

* Within a sys container, it's possible to launch inner containers.

* For each inner container, procfs will be typically mounted at the
  inner container's `/proc` directory.

* As mentioned above, Sysbox traps the mount syscall issued by
  processes inside a sys container, and if it's a new procfs mount, it
  sets up a new mount of the emulated procfs. It does this as follows:

  - The kernel's procfs is mounted within the container; since the
    mount occurs within the context of the inner container's
    namespaces, the kernel will know what resources to expose to the
    inner container.

  - The portions of procfs emulated by Sysbox are also mounted within
    the inner container (e.g., at the inner container's `/proc/sys`,
    `/proc/uptime`, etc.). The manner in which this is done is
    explained later in this doc.

* The emulated procfs mount for an inner container has the following
  characteristics:

  - Accesses to procfs resources that are namespaced by the Linux
    kernel are serviced by the kernel's procfs.

  - Accesses to procfs resources emulated by sysbox in the parent
    sys container are serviced by sysbox-fs. For example:

    - `/proc/uptime` within the inner container is the same as the
      `/proc/uptime` of the parent sys container.

    - `/proc/sys/net/netfilter/nf_conntrack_max` within the inner
      container is the same as the corresponding file in the parent
      sys container.

  - All other accesses are serviced by the kernel's procfs (i.e.,
    accesses to procfs resources that are not namespaced by the Linux
    kernel or emulated sysbox-fs in the parent sys container).

* The above applies more generally to any procfs mount done within a
  sys container, whether it be a procfs mount for an inner container
  or simply a redundant mount of procfs at some arbitrary directory
  within the sys container.

  - For example, if a process within a sys container mounts procfs
    at `/root/proc`, all of the above-mentioned characteristics would
    apply to the newly created mount.

  - Or if a process within a sys container enters a new net namespace
    and mounts procfs at `/root/proc`, the same applies as well.

### proc/sys Emulation

Sysbox-fs emulates `proc/sys` and all the hierarchy beneath it. It does
this in order to gain full control over the contents of `proc/sys`,
including its sub-directories.

The emulation is done as follows:

* If the access is to a kernel resource under `proc/sys` that is
  emulated by sysbox-fs, sysbox-fs performs the emulation action.

  E.g., `/proc/sys/net/netfilter/nf_conntrack_max`

* Otherwise, sysbox-fs does a "passthrough" of the access to the
  kernel's procfs. It does this by entering the namespaces of the
  process performing the access (except the mount namespace), mounts
  the kernel's procfs, and performs the corresponding access on it.

  - Note that the namespaces of the process performing the access may
    not be the same namespaces associated with the sys container.  For
    example, if the process performing the access is inside an inner
    container, then its namespaces are those of the inner container,
    not those of the sys container.

  - The reason the sysbox-fs handler does not enter the mount
    namespace is because it will mount procfs and for isolation and
    security reasons we want to avoid sys container processes from
    seeing that mount.

## Handling Procfs Mounts Inside a Sys Container

This section describes the mechanism used by sysbox to handle
procfs mounts done by processes inside the sys container.

This does not include the initial mount of procfs at the sys
container's `/proc` directory, which is setup via coordination between
sysbox-runc and sysbox-fs at sys container creation time, before
the container's init process runs.

### Mount Syscall Trapping

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

In the case where the syscall emulated, sysbox-fs does the emulation
action and responds to the kernel indicating that it should not
process the mount syscall any further but instead return a value to
the process that invoked it.

In the case where the syscall is not emulated, sysbox-fs responds to
the kernel indicating that it should process the mount syscall as
usual.

### Mount Syscall Emulation

Sysbox-fs only emulates mount syscalls that create **new** procfs
mountpoints inside the sys container.

Mount syscalls that mount other filesystem types, create bind mounts,
or perform remount operations do not require emulation by Sysbox-fs;
those are simply passed to the Linux kernel. Similarly, unmount
operations do not require any action by Sysbox-fs.

For mount syscalls that setup new procfs mountpoints inside the
sys container, sysbox should *ideally* perform the following actions:

* Mount the kernel's procfs at the target path and

* Setup additional sysbox-fs mounts on top of it, just as sysbox does
  on the sys container's `/proc`. In other words, Sysbox would bind
  mount `/var/lib/sysboxfs` to the `proc/sys`, `proc/uptime`, etc. at
  the target procfs mountpoint.

In other words, sysbox would perform actions equivalent to:

```
mount -t proc proc <target-mountpoint>
mount --bind /var/lib/sysboxfs <target-mountpoint>/sys
mount --bind /var/lib/sysboxfs <target-mountpoint>/uptime
mount --bind /var/lib/sysboxfs <target-mountpoint>/swaps
...
```

Note that in order for sysbox to do this, it needs to enter the sys
container's mount namespace yet have access to the host's root
directory (where `/var/lib/sysboxfs` lives). This is not trivial as
described in section [Implementation Challenges](#implementation-challenges);
that same section describes an alternative approach which Sysbox
currently uses.

### Identifying new procfs mounts

To identify a new procfs mount, Sysbox must perform a check on the mount
syscall's `filesystemtype` and `mountflags` as follows:

* The `filesystemtype` must indicate "proc".

* The following `mountflags` must not be set:

  `MS_REMOUNT`, `MS_BIND`, `MS_SHARED`, `MS_PRIVATE`, `MS_SLAVE`, `MS_UNBINDABLE`, `MS_MOVE`.

* See mount(2) for details.

### Path resolution

Sysbox must perform path resolution on the mount's target path, as
described in path_resolution(7). That is, it must be able to resolve
paths that are absolute or relative, and those containing ".", "..",
and symlinks within them.

NOTE: the target mount path is relative to current-working-dir and
root-dir associated with the process performing the mount. The latter
may not necessarily match the sys container's root-dir. Sysbox must
resolve the path accordingly.

### Permission checks

Sysbox must perform permission checking to ensure the process inside
the sys container that is performing the procfs mount operation has
appropriate privileges to do so. The rules are:

* The mounting process must have `CAP_SYS_ADMIN` capability (mounts
  are not allowed otherwise).

* In addition, the mounting process must have search permission on the
  the path from it's current working directory to the target
  directory, or otherwise have `CAP_DAC_READ_SEARCH` and
  `CAP_DAC_OVERRIDE`. See path_resolution(7) for details.

### Mount Flags

The `mount` syscall takes a number of `mountflags` that specify
attributes such as read-only mounts, no-exec, access time handling,
etc. Some of those apply to procfs mounts, most do not.

When emulating new procfs mounts by asking the kernel to mount procfs
at the target directory inside the sys container, Sysbox should pass
the given mount flags to the Linux kernel and let it decide which of
those to honor for the procfs mount.

### Procfs mount options

Per procfs(5), procfs mounts take two mount options: `hidepid` and
`gid`.

These can be set independently for each procfs mountpoint. Ideally,
Sysbox would honor these mount options when procfs is mounted within
the sys container.

Note that these are typically set as follows:

```
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

### Read-only and masked paths in procfs

A sys container typically has some paths under `/proc` configured as read-only or masked.

For example, when launched with Docker, we see `/proc/keys`,
`/proc/timer_list` are masked by bind-mounting the `/dev/null` device
on top of them. Similarly, `/proc/bus`, `/proc/fs` and others are
configured as read-only.

For consistency between procfs mounted by at the sys conatiner's
`/proc` and procfs mounted in other mountpoints inside the sys
container, the same masked paths and read-only paths must be honored
in the other mountpoints.

### Implementation Challenges

In order to implement the solution described above, Sysbox has the
following challenges.

#### Mounting /var/lib/sysboxfs

When Sysbox traps the mount syscall and determines that it's setting
up a new procfs mount inside the sys container, it must request the
kernel to mount procfs at the target mountpoint and then mount
sysbox-fs over portions of that newly mounted procfs.

Mounting sysbox-fs on top of the newly mounted procfs requires that
Sysbox enter the sys container's mount namespace and bind-mount the
host's `/var/lib/sysboxfs`. But the problem is that when the sysbox
process enters the sys container's mount-ns via `setns(2)`, the kernel
does an implicit `chroot` into the sys container's root
directory. Thus, the sysbox process no longer has access to
`/var/lib/sysbox` and is not able to perform the mount.

Overcoming this requires that sysbox spawn a process that enters the
sys container mount namespace before the sys container's init process
does it's pivot root. This way, sysbox can enter the mount namespace
of said process and perform the bind mount of `/var/lib/sysbox` into
the target mountpoint inside the sys container.

An alternative solution is described below.

#### Masked and read-only paths

Another problem is related to masked and read-only paths in the
sys container's `/proc`. Ideally, new mounts of procfs inside
the sys container have the same masked and read-only paths.

This would require sysbox to remember which files or dirs under
`/proc` are configured as read-only or masked during sys container
creation such that those same files/dirs are set accordingly in the
new procfs mountpoint.

#### Sysbox-fs must track multiple mount points

Finally, sysbox-fs would need to understand that for a given sys
container, there are multiple mount points of procfs backed by
sysbox-fs and handle the accesses appropriately.

### Alternative Solution

This solution avoids the challenges associated with mounting
`/var/lib/sysboxfs` inside the sys container by instead bind mounting
the sysbox-fs backed portions of the sys container's `/proc` over the
new procfs mountpoint.

Something equivalent to this command sequence within the sys
container:

```
mount -t proc proc <target-mountpoint>
mount --bind /proc/sys <target-mountpoint>/sys
mount --bind /proc/uptime <target-mountpoint>/uptime
mount --bind /proc/swaps <target-mountpoint>/swaps
```

Pros of this solution:

* Avoids the problem of mounting `/var/lib/sysbox` described previously.

* Supports independent mount flags (e.g., read-only) per procfs
  mountpoint inside the sys container.

* Supports independent mount options (e.g., hidepid) per procfs
  mountpoint inside the sys container.

* Ensures that multiple mounts of procfs within the sys container are
  identical.

Cons of this solution:

* Creates an implicit dependency between all procfs mounts inside the
  sys container and the `/proc` mount inside the sys container.
  For example, a procfs mount at `<target-mountpoint>/sys` depends
  on `/proc/sys` (because the latter is bind mounted on the former).
  This is not ideal, but will likely not matter in practice.

#### Handling of Mount Flags in Alternative Solution

The FUSE mount on `/var/lib/sysboxfs` starts with a number of flags
and data:

```
├─/var/lib/sysboxfs        sysboxfs                      fuse        rw,nosuid,nodev,relatime,user_id=0,group_id=0,allow_other
```

When a sys container is created, the `/var/lib/sysboxfs` dir is
bind-mounted into `/proc/sys` in the sys container, which interits
those flags and data:

```
| |-/proc/sys              sysboxfs[/proc/sys]           fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,allow_other
```

When an inner container is created, sysbox-fs does a bind mount of the
`/proc/sys` in the sys container to the `/proc/sys` in the inner
container; this bind-mount also inherits the above mentioned flags and
data.

If a process in the inner container then wishes to do a remount
operation on `/proc/sys` (commonly done by the inner runc to make
`/proc/sys` are read-only mount, per runc's `readonlyPath()`
function), it will not be aware that `/proc/sys` is already a
bind-mount with existing flags. Thus, it will try to perform the
remount by simply setting the read-only flag. This operation will fail
with "permission denied" because the `mount` syscall detects that the
process is in a user-namespace and it's trying to modify a
mountpoint's flags without honoring existing flags.

To overcome this, sysbox-fs traps the bind-mount and remount
operations when (source = target = "/proc/sys"), enters the mount
namespace of the process doing the syscall, and performs the
bind-mount or remount operation but with the correct flags.

A caveat is that since sysbox-fs only does this for sys container
bind-mount and remount operations whose source=target=/proc/sys, it
works for well inner containers (where proc is mounted at `/proc`), but
does not work well when procfs is mounted at a different path inside
the sys container (e.g., `/root/proc`). In this case a bind-mount or
remount operation on `/root/proc/sys` would fail.

However, such a remount is a rare thing. And the failure only occurs
when doing the remount directly with a syscall that does not honor the
existing mount flags. If done using the "mount" command for example,
things work because this command does honor the existing flags when
doing the remount.

### Procfs Mount Emulation Steps with Alternative Solution

For the alternative solution, Sysbox would follow the following steps
when trapping a mount syscall:

* If the calling process has `CAP_SYS_ADMIN` continue, otherwise
  return an error (EPERM).

* If the syscall indicates

  - A new procfs mount:

    - Emulate as described below

  - Bind-mount or remount on "/proc/sys":

    - Emulate as described below

  - Other:

    - Tell the kernel to procss the mount syscall; no further action
      is necessary.

* Do path resolution & permission checking

  - If this fails, return appropriate error.

* Enter mount ns of the process that made the mount syscall

  - Note that this results in an implicit chroot into the process'
    root-dir.

* For new procfs mounts:

  - Mount procfs at the target mountpoint.

    - Pass in the appropriate flags (e.g., MS_RDONLY) and options (e.g., hidepid)
      that are present in the trapped mount syscall.

  - Create the sysbox-fs bind mounts

    - `/proc/sys` -> `<target-mountpoint>/sys`

    - `/proc/uptime` -> `<target-mountpoint>/uptime`

    - Etc.

  - If this operation fails, return the corresponding error.

  - Set the procfs read-only and masked paths at the target mountpoint.

    - These are obtained from sysbox-runc during container creation.

  - Return success on the mount syscall.

* For bind-mounts or remounts on "/proc/sys" (i.e., source = target = /proc/sys)

  - Read the existing flags for the "/proc/sys" mount

  - If the operation is a bind-mount that is identical to the existing bind-mount on "/proc/sys", ignore it.

  - If the operation is a bind-mount or remount and it modifies flags,
    perform the remount with the logical OR of the existing flags and
    the new flags.

  - Return success on the mount syscall.

* NOTE: since sysbox is emulating the mount syscall, it should follow
  the behavior described in mount(2) and proc(5). It's critical that
  the process invoking the mount syscall does not notice any
  difference between how sysbox handles the syscall and how the Linux
  kernel would handle it.

## Handling Procfs Unmounts Inside a Sys Container

In addition to procfs mounts, Sysbox also traps and emulates procfs
unmount operations.

The purpose of this is the following:

1) Prevent a user from unmounting portions of procfs emulated by sysbox-fs

This is needed as otherwise a user inside a sys container would be
able to unmount the portions of procfs emulated by sysbox-fs and thus
expose the kernel's real procfs inside the sys container. Allowing
this would be both a functional and security problem.

From a functional perspective, it would mean that the sys container
won't work as expected (e.g., reading `/proc/uptime` would return the
host uptime instead of the sys container's uptime, accessing
`/proc/sys/net/netfilter/nf_conntrack_max` would not be possible, etc.)

From a security perspective, it would mean that a process inside the
sys container would be able to obtain information about the host via
`/proc` that would normally be hidden inside the sys container.

2) Ensure that unmounts of procfs inside the sys container work

A root user inside the sys container is allowed to unmount procfs
(just as a root user in a real host would be). In practice this is
rare, but it's possible.

In order to support this, Sysbox must trap and emulate the unmount
procfs syscall, and perform the unmount of the sys container's procfs
by first unmounting the portions of procfs that are emulated by
sysbox-fs, and then unmounting the kernel's procfs.

In other words, since a procfs mounts inside the sys container are
trapped and cause sysbox to perform the following sequence of operations:

```
mount -t proc proc <target-mountpoint>
mount --bind /proc/sys <target-mountpoint>/sys
mount --bind /proc/uptime <target-mountpoint>/uptime
mount --bind /proc/swaps <target-mountpoint>/swaps
```

it follows that procfs unmounts inside the sys container results in
the reverse sequence of operations:

```
umount <target-mountpoint>/swaps
umount <target-mountpoint>/uptime
umount <target-mountpoint>/sys
umount <target-mountpoint>
```


Sysbox-fs only emulates unmount syscalls which operate on procfs
mountpoints or the sub-portions of procfs backed by sysbox-fs.

### Sysbox-fs emulates the umount and umount2 syscalls

Linux supports two syscalls to perform unmounts: `umount` and
`umount2`. They only differ in that the latter takes a `flags`
argument controlling the behavior of the unmount operation
(e.g., `MNT_FORCE`, `MNT_DETACH`, `MNT_EXPIRE`, and `UMOUNT_NOFOLLOW`).

Sysbox-fs emulates *both* of these system calls. For `umount2`,
sysbox-fs honors the `flags` arguments by performing the corresponding
unmounts using the same flags.

Note that the `UMOUNT_NOFOLLOW` flag requires that the `umount2`
syscall does not dereference the unmount target if it's a symbolic
link.

### Procfs Unmount Emulation Steps

* If the calling process has `CAP_SYS_ADMIN` continue, otherwise
  return an error (EPERM).

* Do path resolution & permission checking

  - If path resolution fails, return an appropriate error.

  - NOTE: if the syscall is umount2 with flag `UMOUNT_NOFOLLOW`, then
    path resolution must not dereference the target mountpoint if it's
    a symlink.

* Enter mount ns of the process that made the unmount syscall

  - Note that this results in an implicit chroot into the process'
    root-dir.

* Check the unmount target:

  - If the target is a procfs mount (e.g., sysbox-fs can find this via `/proc/self/mountinfo` by searching for mounttype "proc")

    - Emulate as described below.

  - If the target is a sysbox-fs mountpoint under a procfs mount (e.g.,
    `/proc/sys`, `/proc/uptime`, etc.):

    - Return `EINVAL` (the purpose of this is described in (1) above)

  - Other:

    - Tell the kernel to procss the unmount syscall; no further action
      is necessary.

* At this point we know the unmount target is a procfs mountpoint;
  sysbox-fs does the following:

  - Unmount the portions of procfs emulated by sysbox-fs:

    ```
    umount <target-mountpoint>/swaps
    umount <target-mountpoint>/uptime
    umount <target-mountpoint>/sys
    ```

  - Unmount procfs itself:

    ```
    umount <target-mountpoint>
    ```

  - When doing the above unmounts, use the `umount` or `umount2`
    syscall as appropriate depending on the syscall that we are
    emulating.

  - If emulating `umount2`, then do the above unmounts using the same
    flags that the trapped syscall uses (e.g., `MNT_DETACH`, etc).

  - Return success on the syscall or failure if any of the above steps
    fails.

* NOTE: since sysbox is emulating the umount or umount2 syscall, it
  should follow the behavior described in umount(2). It's critical
  that the process invoking the syscall does not notice any difference
  between how sysbox handles the syscall and how the Linux kernel
  would handle it.
