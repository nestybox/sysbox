# Sysbox User Guide: Functional Limitations

This document describes functional restrictions and limitations of Sysbox and
the containers created by it.

## Contents

-   [Sysbox Container Limitations](#sysbox-container-limitations)
-   [Docker Restrictions](#docker-restrictions)
-   [Kubernetes Restrictions](#kubernetes-restrictions)
-   [Sysbox Functional Limitations](#sysbox-functional-limitations)

## Sysbox Container Limitations

Sysbox enables containers to run applications or system software such as
systemd, Docker, Kubernetes, K3s, etc., seamlessly & securely (e.g., no
privileged containers, no complex setups).

While our goal is for Sysbox containers to run **any software that runs on
bare-metal or VMs**, this is still a work-in-progress.

Thus, there are some limitations at this time. The table below describes these.

| Limitation    | Description       | Affected Software | Planned Fix |
| --------      | --------------- | ----- | :--: |
| mknod         | Fails with "operation not permitted". | Software that creates devices such as /dev/tun, /dev/tap, /dev/fuse, etc. | WIP |
| binfmt-misc   | Fails with "permission denied". | Software that uses /proc/sys/fs/binfmt_misc inside the container (e.g., buildx+QEMU for multi-arch builds). | WIP |
| Nested user-namespace | `unshare -U --mount-proc` fails with "invalid argument". | Software that uses the Linux user-namespace (e.g., Docker + userns-remap). Note that the Sysbox container is rootless already, so this implies nesting Linux user-namespaces. | Yes |
| Host device access | Host devices exposed to the container (e.g., `docker run --devices ...`) show up with "nobody:nogroup" ownership. Thus, access to them will fail with "permission denied" unless the device grants read/write permissions to "others". | Software that needs access to hardware accelerators. | Yes |
| rpc-pipefs    | Mounting rpc-pipefs fails with "permission denied". | Running an NFS server inside the Sysbox container. | Yes |
| insmod        | Fails with "operation not permitted". | Can't load kernel modules from inside containers. | TBD |

**NOTES:**

-   "WIP" means the fix is being worked-on right now. "TBD" means a
    decision is yet to be made.

-   If you find other software that fails inside the Sysbox container, please open
    a GitHub issue so we can add it to the list and work on a fix.

## Docker Restrictions

This section describes restrictions when using Docker + Sysbox.

These restrictions are in place because they reduce or break container-to-host
isolation, which is one of the key features of Sysbox.

Note that some of these options (e.g., --privileged) are typically needed when
running complex workloads in containers. With Sysbox, this is no longer needed.

| Limitation    | Description     | Comment |
| ----------    | --------------- | ------- |
| docker --privileged | Does not work with Sysbox | Breaks container-to-host isolation. |
| docker --userns=host | Does not work with Sysbox | Breaks container-to-host isolation. |
| docker --pid=host | Does not work with Sysbox | Breaks container-to-host isolation. |
| docker --net=host | Does not work with Sysbox | Breaks container-to-host isolation. |

## Kubernetes Restrictions

This section describes restrictions when using Kubernetes + Sysbox.

Some of these restrictions are in place because they reduce or break
container-to-host isolation, which is one of the key features of Sysbox.

Note that some of these options (e.g., privileged: true) are typically needed when
running complex workloads in pods. With Sysbox, this is no longer needed.

| Limitation    | Description     | Comment |
| ----------    | --------------- | ------- |
| privileged: true  | Not supported in pod security context | Breaks container-to-host isolation. |
| hostNetwork: true  | Not supported in pod security context | Breaks container-to-host isolation. |
| hostIPC: true  | Not supported in pod security context | Breaks container-to-host isolation. |
| hostPID: true  | Not supported in pod security context | Breaks container-to-host isolation. |

## Sysbox Functional Limitations

| Limitation    | Description     | Planned Fix |
| ----------    | --------------- | ------- |
| Sysbox must run as root | Sysbox needs root privileges on the host to perform the advanced OS virtualization it provides (e.g., procfs/sysfs emualtion, syscall trappings, etc.) | TBD |
| Container Checkpoint/Restore | Not yet supported | Yes |
| Sysbox Nesting | Running Sysbox inside a Sysbox container is not supported | TBD |
