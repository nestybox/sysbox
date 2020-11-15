# Sysbox Distro Compatibility

## Contents

-   [Supported Linux Distros](#supported-linux-distros)
-   [Sysbox Operational Modes](#Sysbox-Operational-Modes)
-   [Kernel Upgrade Procedures](#Kernel-Upgrade-Procedures)

## Supported Linux Distros

Sysbox relies on functionality that is only present in relatively modern Linux
kernels.

In Ubuntu's case, these requirements are met starting with Kernel 5.0. For
the rest of the Sysbox's supported distributions, Kernel 5.5+ is required.

The following table summarizes the Linux distributions being supported as well
as the operational modes (`shiftfs` vs `userns-remap`) being allowed. For
scenarios where a kernel upgrade is required, refer to the corresponding
upgrade procedure further below.

<p align="center">
    <img alt="sysbox" src="figures/distro-support-matrix.png" width="1000x" />
</p>

* Note 1: Ubuntu Bionic requires no kernel upgrade in scenarios where relatively
recent releases have been installed (i.e. 18.04.4+). If that's not the
case, user will need to upgrade the kernel. Refer to [Ubuntu's kernel-upgrade](#Ubuntu-Kernel-Upgrade)
procedure for details.

* Note 2: Fedora 31 requires no kernel upgrade assuming that user is running a recent
installation (i.e. kernel 5.5+ is deployed). Otherwise, a kernel-upgrade will be
expected. Refer to [Fedora's kernel-upgrade](#Fedora-kernel-upgrade) procedure for details.

## Sysbox Operational Modes

Sysbox runtime relies on kernel's user-namespace feature to secure system
containers. There are two approaches utilized by Sysbox to manage the creation
of these user-namespaces: `shiftfs` and `userns-remap`.

### Shiftfs Mode

Recent Ubuntu kernels carry a module called `shiftfs` that Sysbox uses as part of
its container isolation strategy.

With `shiftfs`, Sysbox can create containers that use the user-namespace for
strong isolation without requiring the higher level container manager to do this
explicitly (e.g. without enabling userns-remap mode in Docker).

This is the default operational mode in scenarios where `shiftfs` kernel module
is present. Refer to the Sysbox [installation guide](user-guide/install.md) for more details.

### Userns-remap Mode

In scenarios where `shiftfs` module is not found, Sysbox requires Docker to be
configured in in [userns-remap mode](https://docs.docker.com/engine/security/userns-remap/). At the moment this applies to all the non-Ubuntu releases supported
by Sysbox, as well as Ubuntu-Cloud images utilized by some Cloud Providers.

In this scenario, no configuration is expected from the user. Upon detection of
`shiftfs` absence, the Sysbox installer will offer the user the possibility
to automatically configure Docker to operate in userns-remap mode.

Refer to the Sysbox [installation guide](user-guide/install.md) for more details.

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

```
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

```
$ sudo dnf config-manager --set-enabled kernel-vanilla-mainline

$ sudo dnf update

$ sudo shutdown -r now
```

Refer to this [link](https://www.cloudinsidr.com/content/how-to-upgrade-the-linux-kernel-in-fedora-29/) for more details.

### CentOS Kernel Upgrade

Applicable to CentOS 8 release.

```
$ sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org

$ sudo dnf install https://www.elrepo.org/elrepo-release-8.0-2.el8.elrepo.noarch.rpm

$ sudo dnf --enablerepo=elrepo-kernel install kernel-ml

$ sudo shutdown -r now
```

Refer to this [link](https://vitux.com/how-to-upgrade-the-kernel-on-centos-8-0/) for more details.