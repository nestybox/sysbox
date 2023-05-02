# Sysbox Distro Compatibility

## Contents

-   [Supported Linux Distros](#supported-linux-distros)
-   [Supported Platform Architectures](#supported-platform-architectures)
-   [Shiftfs Requirement](#shiftfs-requirement)
-   [Kernel Upgrade Procedures](#kernel-upgrade-procedures)

## Supported Linux Distros

The following table summarizes the supported Linux distros, the installation
methods supported, and any other requirements:

| Distro / Release      | Package Install | K8s Install | Build from Source | Min Kernel | Shiftfs Required | Other |
| --------------------- | :-------------: | :---------: | :---------------: | :--------: | :--------------: | ----- |
| Ubuntu Bionic (18.04) | ✓               | ✓           | ✓                 | 5.3+       | If kernel < 5.12 | [Kernel upgrade notes](#ubuntu-kernel-upgrade) |
| Ubuntu Focal  (20.04) | ✓               | ✓           | ✓                 | 5.4+       | If kernel < 5.12 | |
| Ubuntu Jammy (22.04)  | ✓               | ✓           | ✓                 | 5.15+      | No (but recommended) | |
| Debian Buster (10)    | ✓               | WIP         | ✓                 | 5.5+       | If kernel < 5.12 | [Kernel upgrade notes](#debian-kernel-upgrade) |
| Debian Bullseye (11)  | ✓               | WIP         | ✓                 | 5.5+       | If kernel < 5.12 | |
| Fedora (34 to 37)     | WIP             | WIP         | ✓                 | 5.12+      | No | |
| Rocky Linux 8         | WIP             | WIP         | ✓                 | 5.12+      | No | |
| Alma Linux (8, 9)     | WIP             | WIP         | ✓                 | 5.12+      | No | |
| CentOS Stream         | WIP             | WIP         | ✓                 | 5.12+      | No | |
| Amazon Linux 2        | WIP             | WIP         | ✓                 | 5.12+      | No | [Kernel upgrade notes](https://repost.aws/knowledge-center/amazon-linux-2-kernel-upgrade) |
| RedHat Enterprise     | WIP             | WIP         |                   | 5.12+      | No | Sysbox-EE only |
| Flatcar               | ✓               | ✓           |                   | 5.10+      | If kernel < 5.12  | Sysbox-EE only; see [here](user-guide/install-flatcar.md). |

**NOTES:**

-   "Package install" means a Sysbox package is available for that distro. See
    [here](user-guide/install-package.md) for more.

-   "K8s-install" means you can deploy Sysbox on a Kubernetes worker node based
    on that distro. See [here](user-guide/install-k8s.md) for more.

-   "Build from source" means you can build and install Sysbox from source on
    that distro. It's pretty easy, see [here](developers-guide/README.md).

-   "Kernel upgrade" means a kernel upgrade may be required (Sysbox requires a
    fairly new kernel). See [below](#kernel-upgrade-procedures) for more.

-   "WIP" means "work-in-progress" (i.e., we expect to have this soon).

-   These are the Linux distros we officially support (and test with). However,
    we expect Sysbox to work fine on other Linux distros too, particularly with
    kernel >= 5.12.

## Supported Platform Architectures

* See [here](arch-compat.md) for a list of supported platform architectures
  (e.g., amd64, arm64).

## Shiftfs Requirement

Shiftfs is a Linux kernel module that Sysbox uses to ensure host volumes mounted
into the (rootless) container show up with proper user and group IDs (rather
than `nobody:nogroup`); see the [User Guide's Design Chapter](user-guide/design.md)
for more info.

Sysbox's requirement for shiftfs is as follows:

| Linux Kernel Version | Shiftfs Required by Sysbox |
| -------------------- | :------------------------: |
| < 5.12               | Yes |
| 5.12 to 5.18         | No (but recommended) |
| >= 5.19              | No |

In kernels 5.12 to 5.18, shiftfs is not required but having it causes Sysbox to
setup the container's filesystem more efficiently, so it's recommended.

Unfortunately, shiftfs is only available in Ubuntu, Debian, and Flatcar distros
(and possibly derivatives of these). Therefore, if your host has kernel < 5.12
and you wish to use Sysbox, it must be one of these distros.

Shiftfs is not available in other distros (e.g., Fedora, CentOS, RedHat, Amazon
Linux 2, etc.) For this reason, in order to use Sysbox in these other distros,
you must have kernel >= 5.12.

### Shiftfs Installation

In the Ubuntu's desktop and server versions, shiftfs comes pre-installed. In
Ubuntu's cloud images or in Debian or Flatcar, shiftfs must be manually
installed. See the [User Guide's Installation Chapter](user-guide/install-package.md)
for info on how to do this.

## Kernel Upgrade Procedures

### Ubuntu Kernel Upgrade

If you have a relatively old Ubuntu 18.04 release (e.g. 18.04.3), you need to upgrade the kernel to >= 5.3.

We recommend using Ubuntu's [LTS-enablement](https://wiki.ubuntu.com/Kernel/LTSEnablementStack) package to do the upgrade as follows:

```console
$ sudo apt-get update && sudo apt install --install-recommends linux-generic-hwe-18.04 -y

$ sudo shutdown -r now
```

### Debian Kernel Upgrade

This one is only required when running Debian Buster.

```console
$ # Allow debian-backports utilization ...

$ echo deb http://deb.debian.org/debian buster-backports main contrib non-free | sudo tee /etc/apt/sources.list.d/buster-backports.list

$ sudo apt update

$ sudo apt install -t buster-backports linux-image-amd64

$ sudo shutdown -r now
```

Refer to this [link](https://wiki.debian.org/HowToUpgradeKernel) for more details.
