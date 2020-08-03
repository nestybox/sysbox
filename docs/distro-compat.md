# Sysbox Distro Compatibility

## Contents

-   [Supported Linux Distros](#supported-linux-distros)
-   [Ubuntu Support](#ubuntu-support)

## Supported Linux Distros

Sysbox relies on functionality that is currently only present in Ubuntu Linux.
As a result Ubuntu is the only distro supported at this time. We are working
on adding support for more distros.

## Ubuntu Support

Sysbox requires recent Ubuntu versions:

-   Ubuntu 20.04 "Focal Fossa"
-   Ubuntu 19.10 "Eoan Ermine"
-   Ubuntu 18.04 "Bionic Beaver" (point releases older than 18.04.4 require kernel upgrade)

These versions carry some new Linux kernel features that Sysbox relies on to
create the system containers.

**NOTE:** If you have a relatively old Ubuntu 18.04 release (e.g. 18.04.3), you need to upgrade the kernel to >= 5.0.
We recommend using Ubuntu's [LTS-enablement](https://wiki.ubuntu.com/Kernel/LTSEnablementStack)
package to do the upgrade as follows:

```console
$ sudo apt-get update && sudo apt install --install-recommends linux-generic-hwe-18.04 -y
```

### Using Sysbox On Kernels Without the Shiftfs Module

Recent Ubuntu kernels carry a module called `shiftfs` that Sysbox uses as part
of its container isolation strategy.

However, some Ubuntu cloud images do not carry the module. In this case, Sysbox
requires that Docker be configured in [userns-remap mode](https://docs.docker.com/engine/security/userns-remap/).

The Sysbox installer will detect this condition and can automatically put
Docker in userns-remap mode if desired. See [here](user-guide/install.md#docker-userns-remap) for details.
