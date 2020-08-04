# Sysbox Quick Start Guide: Security

This section shows system container security features by way of example.

The [User Guide](../user-guide/security.md) describes this topic
deeper detail.

## System Container Isolation Features

We show the following system container isolation features:

-   Linux user namespace

-   Linux capabilities

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

This means that user-IDs in the range [0:65535] inside the container are mapped
to a range of unprivileged user-IDs on the host (chosen by Sysbox). In this
example they map to the host user-ID range [268994208 : 268994208+65535].

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

1) The container's root process is limited in what it can do within the container.

2) The container's root process has those same capabilities on the host, which
   poses a higher security risk should the process escape the container's chroot
   jail.

System containers overcome both of these drawbacks.
