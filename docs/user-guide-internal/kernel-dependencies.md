# Sysbox Internal User Guide: Kernel Dependencies

Document's goal is to highlight the set of dependencies that Sysbox
implementation has over Linux kernel, and the 'distros' where these
requirements are met.

## Allow overlayfs mounts on unprivileged user-namespaces

As of today, Ubuntu and now Debian, seem to be the only distros allowing this
feature.

Supported Kernels:

-   Ubuntu Kernel 5.x+
-   Debian Kernel [5.2.x](https://salsa.debian.org/kernel-team/linux/blob/master/debian/patches/debian/overlayfs-permit-mounts-in-userns.patch): Allows users to enable this feature through sysctl configuration.

To-do:

-   Evaluate Debian's 5.2.x.

## Shiftfs

No indication found of other distros looking into 'shiftfs'. However, there
seems to be an incipient interest in [fuse-overlayfs](https://github.com/containers/fuse-overlayfs) feature to offer similar functionality (see [here](https://developers.redhat.com/blog/2019/08/14/best-practices-for-running-buildah-in-a-container/)).

Supported Kernels:

-   Ubuntu 5.x+

To-do:

-   Evaluate fuse-overlayfs.

## Implementation of `SECCOMP_USER_NOTIF_FLAG_CONTINUE`

Required for syscall-trapping functionality.

Supported Kernels:

-   Ubuntu Kernel 5.0.0-22+
-   Upstream Kernel [5.5.x](https://github.com/torvalds/linux/commit/fb3c5386b382d4097476ce9647260fc89b34afdb)

To-do:

-   Not much; just keep an eye on upcoming distro-releases -- Debian Bullseye
    (Apr 2020) may include 5.5.x kernel.
