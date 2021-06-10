# Sysbox Distro Compatibility

## Contents

-   [Supported Linux Distros](#supported-linux-distros)
-   [Kernel Upgrade Procedures](#kernel-upgrade-procedures)
-   [Cgroups v1 Booting Procedure](#cgroups-v1-booting-procedure)

## Supported Linux Distros

The following table summarizes the supported Linux distros, the installation
methods supported, and any other requirements:

| Distro / Release      | Package Install | K8s Install | Build from Source | Kernel Upgrade | Other Requirements |
| --------------------- | :-------------: | :---------: | :------------: | :----: | :---- |
| Ubuntu Bionic (18.04) | ✓ | ✓ | ✓ | [Maybe](#ubuntu-kernel-upgrade) | |
| Ubuntu Focal  (20.04) | ✓ | ✓ | ✓ | No                              | |
| Debian Buster (10)    | ✓ |   | ✓ | [Yes](#debian-kernel-upgrade)   | |
| Debian Bullseye (11)  | ✓ |   | ✓ | No                              | Must boot with [cgroups v1](#debian-cgroups-v1-config). |
| Fedora 31             |   |   | ✓ | [Maybe](#fedora-kernel-upgrade) | Must boot with [cgroups v1](#fedora-cgroups-v1-config). |
| Fedora 32             |   |   | ✓ | Yes                             | Must boot with [cgroups v1](#fedora-cgroups-v1-config). |
| CentOS 8              |   |   | ✓ | [Yes](#centos-kernel-upgrade)   | |

**NOTES:**

-   "Package install" means a Sysbox package is available for that distro. See [here](user-guide/install-package.md) for more.

-   "K8s-install" means you can deploy Sysbox on a Kubernetes worker node based on that distro. See [here](user-guide/install-k8s.md) for more.

-   "Build from source" means you can build and install Sysbox from source on that distro. It's pretty easy, see [here](developers-guide/README.md).

-   "Kernel upgrade" means a kernel upgrade may be required (Sysbox requires a fairly new kernel). See [below](#kernel-upgrade-procedures) for more.

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

## Cgroups v1 Booting Procedure

Sysbox does not yet support cgroups v2 (it only supports cgroups v1). In some distros,
cgroups v2 is now the default. To use Sysbox in these machines, you must reboot them
with cgroups v1. The subsections below show how to do this.

**NOTE:** we plan to add cgroups v2 support to Sysbox very soon.

### Debian cgroups v1 Config

To boot the Debian kernel with cgroups v1, set kernel parameter
`systemd.unified_cgroup_hierarchy=0` as follows and reboot the kernel.

```console
$ sudo sh -c 'echo GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=0" >> /etc/default/grub'
$ sudo update-grub
```

### Fedora cgroups v1 Config

To boot the Fedora kernel with cgroups v1, set kernel parameter
`systemd.unified_cgroup_hierarchy=0` as follows and reboot the kernel.

```console
sudo dnf install grubby
sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
```
