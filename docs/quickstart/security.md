# Sysbox Quick Start Guide: Security

This section shows system container security features by way of example.

The [User Guide](../user-guide/security.md) describes this topic
deeper detail.

## System Container Isolation Features

We show the following system container isolation features:

-   Linux user namespace

-   Linux capabilities

-   Immutable Mountpoints

-   Exclusive Userns ID Mappings (Sysbox-EE only)

First let's deploy a system container:

```console
$ docker run --runtime=sysbox-runc --rm -it --hostname syscont debian:latest
root@syscont:/#
```

Nestybox system containers always use the Linux user-namespace (in fact
they use all Linux namespaces) to provide strong isolation between the
system container and the host.

Let's verify this by comparing the namespaces between a process inside
the system container and a process on the host.

From the system container:

```console
root@syscont:/# ls -l /proc/self/ns/
total 0
lrwxrwxrwx 1 root root 0 Oct 23 22:06 cgroup -> 'cgroup:[4026532563]'
lrwxrwxrwx 1 root root 0 Oct 23 22:06 ipc -> 'ipc:[4026532506]'
lrwxrwxrwx 1 root root 0 Oct 23 22:06 mnt -> 'mnt:[4026532504]'
lrwxrwxrwx 1 root root 0 Oct 23 22:06 net -> 'net:[4026532509]'
lrwxrwxrwx 1 root root 0 Oct 23 22:06 pid -> 'pid:[4026532507]'
lrwxrwxrwx 1 root root 0 Oct 23 22:06 pid_for_children -> 'pid:[4026532507]'
lrwxrwxrwx 1 root root 0 Oct 23 22:06 user -> 'user:[4026532503]'
lrwxrwxrwx 1 root root 0 Oct 23 22:06 uts -> 'uts:[4026532505]'
```

Now from the host:

```console
ls -l /proc/self/ns
total 0
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 cgroup -> 'cgroup:[4026531835]'
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 ipc -> 'ipc:[4026531839]'
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 mnt -> 'mnt:[4026531840]'
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 net -> 'net:[4026531992]'
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 pid -> 'pid:[4026531836]'
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 pid_for_children -> 'pid:[4026531836]'
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 user -> 'user:[4026531837]'
lrwxrwxrwx 1 chino chino 0 Oct 23 22:07 uts -> 'uts:[4026531838]'
```

You can see the system container uses dedicated namespaces, including
the user and cgroup namespaces. It has no namespaces in common with
the host, which gives it stronger isolation compared to regular Docker
containers.

Because system containers use the Linux user-namespace, it means
that the root user in the container only has privileges on resources
assigned to the container, but none otherwise.

You can verify this by typing the following inside the system container:

```console
root@syscont:/# cat /proc/self/uid_map
         0  268994208      65536
root@syscont:/# cat /proc/self/gid_map
         0  268994208      65536
```

This means that user-IDs in the range \[0:65535] inside the container are mapped
to a range of unprivileged user-IDs on the host (chosen by Sysbox). In this
example they map to the host user-ID range \[268994208 : 268994208+65535].

Sysbox assigns all containers the same user-ID mappings. Sysbox Enterprise
Edition (Sysbox-EE) improves on this as described in the next section.

Now, let's check the capabilities of a process created by the root user inside
the system container:

```console
root@syscont:/# grep Cap /proc/self/status
CapInh: 0000003fffffffff
CapPrm: 0000003fffffffff
CapEff: 0000003fffffffff
CapBnd: 0000003fffffffff
CapAmb: 0000003fffffffff
```

As shown, a root process inside the system container has all capabilities
enabled, but those capabilities only take effect with respect to host
resources assigned to the system container.

Contrast this to a regular Docker container. A root process in such a
container has a reduced set of capabilities (typically `CapEff:
00000000a80425fb`) and does not use the Linux user namespace. This has
two drawbacks:

1.  The container's root process is limited in what it can do within the container.

2.  The container's root process has those same capabilities on the host, which
    poses a higher security risk should the process escape the container's chroot
    jail.

System containers overcome both of these drawbacks.

### Immutable Mountpoints \[ +v0.3.0 ]

Filesystem mounts that make up the [system container's rootfs jail](../user-guide/security.md#root-filesystem-jail)
(i.e., mounts setup at container creation time into the container's root
filesystem) are considered special, meaning that Sysbox places restrictions on
the operations that may be done on them from within the container.

This ensures processes inside the container can't modify those mounts in a way
that would weaken or break container isolation, even though these processes may
be running as root with full capabilities inside the container and thus have
access to the `mount` and `umount` syscalls.

We call these "immutable mounts". The
[user-guide](../user-guide/security.md#initial-mount-immutability--v030-) has a
full description of this feature. Here we just show an example of what this
feature does.

1.  Deploy a system container with a read-only mount of host volume `myvol`:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname=syscont -v myvol:/mnt/myvol:ro ubuntu
root@syscont:/#
```

2.  List the container's initial mounts; these are all considered immutable
    because they are setup at container creation time by Sysbox.

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

3.  Let's try to remount one of those immutable read-only mounts to read-write:

```console
root@syscont:/# mount -o remount,rw,bind /mnt/myvol
mount: /mnt/myvol: permission denied.
```

This operation fails, even though the process doing the remount is root inside
the container with all capabilities enabled:

```console
root@syscont:/# cat /proc/self/status | egrep "Uid|Gid|CapEff"
Uid:    0       0       0       0
Gid:    0       0       0       0
CapEff: 0000003fffffffff
```

The reason the operation fails is that Sysbox detects the remount operation
occurs over an immutable read-only mount. Thus, it can't be remounted read-write
from inside the container (as doing so would essentially break container
isolation).

Under the covers, Sysbox does this by trapping the mount system call and vetting
the action.

4.  On the other hand, immutable read-write mounts **can** be remounted
    read-only. This is allowed because such a remount places a stronger
    restriction on the immutable mount, rather than a weaker one:

```console
root@syscont:/# mount -o remount,ro,bind /etc/resolv.conf

root@syscont:/# findmnt | grep resolv.conf
|-/etc/resolv.conf                                           /var/lib/docker/containers/080fb5dbe347a947accf7ba27a545ce11d937f02f02ec0059535cfc065d04ea0[/resolv.conf] shiftfs  ro,relatime
```

5.  The mount restrictions also apply to bind-mounts sourced from initial
    mounts inside the container. For example:

```console
root@syscont:/# mkdir /root/headers

root@syscont:/# mount --bind /usr/src/linux-headers-5.4.0-65 /root/headers

root@syscont:/# mount -o remount,bind,rw /root/headers
mount: /root/headers: permission denied.
```

This fails because the source of the bind mount (`/usr/src/linux-headers-5.4.0-65`)
is an initial read-only mount of the container. Since the bind mount simply
makes that initial read-only mount show up somewhere else in the container's
filesystem, the bind mount is also considered immutable.

6.  Finally, the mount restrictions do not apply to new mounts created inside the
    container. Those are not initial mounts, so no restrictions are placed on them:

```console
root@syscont:/# mkdir /root/tmp
root@syscont:/# mount -t tmpfs -o ro,size=10M tmpfs /root/tmp
root@syscont:/# mount -o remount,rw,bind /root/tmp
```

This works without problem because the mount at `/root/tmp` is a new mount
(i.e., it was not setup by Sysbox at container creation time). Thus it's
not considered immutable.

In the prior example with only looked at remount operations. But how about
unmounts?

By default, unmounts of initial mounts are **not** restricted in the same way
that remount operations are. The reason for this is that system container images
often have a process manager inside, and some process managers (in particular
systemd) unmount all mountpoints inside the container during container stop. If
Sysbox where to restrict these unmounts, the process manager will report errors
during container stop such as:

```console
[FAILED] Failed unmounting /etc/hostname.
[FAILED] Failed unmounting /etc/hosts.
[FAILED] Failed unmounting /etc/resolv.conf.
[FAILED] Failed unmounting /usr/lib/modules/5.4.0-62-generic.
[FAILED] Failed unmounting /usr/src/linux-headers-5.4.0-62.
[FAILED] Failed unmounting /usr/src/linux-headers-5.4.0-62-generic.
```

Note that allowing unmounts of immutable mounts is typically not a security
concern, because the unmount normally exposes the underlying contents of the
system container's image, and this image will likely not have sensitive
data that is masked by the mounts. For example:

```console
root@syscont:/# grep nameserver /etc/resolv.conf
nameserver 75.75.75.75
nameserver 75.75.76.76

root@syscont:/# umount /etc/resolv.conf

root@syscont:/# grep nameserver /etc/resolv.conf
(empty)
```

Having said this, this behavior can be changed by setting the sysbox-fs config
option `allow-immutable-unmounts=false`. When this option is set, Sysbox does
restrict unmounts on all immutable mounts:

```console
root@syscont:/# umount /etc/resolv.conf
umount: /etc/resolv.conf: must be superuser to unmount.
```

Of course, mounts that are not immutable are not affected by this restriction:

```console
root@syscont:/# mkdir /root/tmp
root@syscont:/# mount -t tmpfs -o ro,size=10M tmpfs /root/tmp
root@syscont:/# umount /root/tmp
```

The [user-guide](../user-guide/security.md#initial-mount-immutability--v030-)
has more info on this.

***
#### ** --- Sysbox-EE Feature Highlight --- **

### Exclusive User-ID Mappings

Sysbox-EE improves on Sysbox-CE by automatically assigning each system container
exclusive user-ID and group-ID mappings. This further isolates system containers
from the host and from each other.

For example, if you launch a couple of containers with Docker and Sysbox-EE,
you'll see they are both assigned exclusive user-ID and group-ID mappings.

In the first container:


```console
root@syscont:/# cat /proc/self/uid_map
         0  268994208      65536
root@syscont:/# cat /proc/self/gid_map
         0  268994208      65536
```

In the second container:

```console
$ docker run --runtime=sysbox-runc --rm -it --hostname syscont2 debian:latest

root@syscont2:/# cat /proc/self/uid_map
         0  269059744      65536
root@syscont2:/# cat /proc/self/gid_map
         0  269059744      65536
```

This capability of Sysbox-EE provides enhanced cross-container isolation: if
a process in one container somehow escapes the container, it will find itself
with no permissions to access any data in other containers or on the host.

More info on this can be found in the [Sysbox User Guide](../user-guide/security.md#user-namespace-id-mapping).

***
