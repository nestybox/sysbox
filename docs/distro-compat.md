# Sysbox Distro Compatibility

## Contents

-   [Supported Linux Distros](#supported-linux-distros)
-   [Kernel Upgrade Procedures](#kernel-upgrade-procedures)

## Supported Linux Distros

The following table summarizes the supported Linux distros, the installation
methods supported, and any other requirements:

| Distro / Release      | Package Install | K8s Install | Build from Source | Kernel Upgrade | Other |
| --------------------- | :-------------: | :---------: | :------------: | :----: | :----: |
| Ubuntu Bionic (18.04) | ✓ | ✓ | ✓ | [Maybe](#ubuntu-kernel-upgrade) | |
| Ubuntu Focal  (20.04) | ✓ | ✓ | ✓ | No                              | |
| Debian Buster (10)    | ✓ |   | ✓ | [Yes](#debian-kernel-upgrade)   | |
| Debian Bullseye (11)  | ✓ |   | ✓ | No                              | |
| Fedora 31 (EOL)       |   |   | ✓ | [Maybe](#fedora-kernel-upgrade) | |
| Fedora 32 (EOL)       |   |   | ✓ | No                              | |
| Fedora 33             |   |   | ✓ | No                              | |
| Fedora 34             |   |   | ✓ | No                              | |
| CentOS 8              |   |   | ✓ | [Yes](#centos-kernel-upgrade)   | |
| Flatcar               | N/A |   | ✓ | No                            | More details [here](https://github.com/nestybox/sysbox-flatcar-preview) |

**NOTES:**

-   "Package install" means a Sysbox package is available for that distro. See [here](user-guide/install-package.md) for more.

-   "K8s-install" means you can deploy Sysbox on a Kubernetes worker node based on that distro. See [here](user-guide/install-k8s.md) for more.

-   "Build from source" means you can build and install Sysbox from source on that distro. It's pretty easy, see [here](developers-guide/README.md).

-   "Kernel upgrade" means a kernel upgrade may be required (Sysbox requires a fairly new kernel). See [below](#kernel-upgrade-procedures) for more.

- "EOL" releases refer to those that are being deprecated by its distro vendor as
part of their release scheduling process.

## Kernel Upgrade Procedures

### Ubuntu Kernel Upgrade

If you have a relatively old Ubuntu 18.04 release (e.g. 18.04.3), you need to upgrade the kernel to >= 5.0.

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

### Fedora Kernel Upgrade

This is only applicable to Fedora 31 release; more recent releases already
include 5.5+ kernels.

```console
$ sudo dnf config-manager --set-enabled kernel-vanilla-mainline

$ sudo dnf update

$ sudo shutdown -r now
```

Refer to this [link](https://www.cloudinsidr.com/content/how-to-upgrade-the-linux-kernel-in-fedora-29/) for more details.

### CentOS Kernel Upgrade

Applicable to CentOS 8 release.

```console

$ sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org

$ sudo dnf install https://www.elrepo.org/elrepo-release-8.0-2.el8.elrepo.noarch.rpm

$ sudo dnf --enablerepo=elrepo-kernel install kernel-ml

$ sudo shutdown -r now
```

Refer to this [link](https://vitux.com/how-to-upgrade-the-kernel-on-centos-8-0/) for more details.
