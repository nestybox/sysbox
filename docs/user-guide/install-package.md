# Sysbox User Guide: Installation with the Sysbox Package

This document describes how to install Sysbox using the [packaged versions](https://github.com/nestybox/sysbox/releases).

This is usually the case when installing Sysbox on hosts that have Docker in
them.

**NOTE: If you are installing Sysbox on a Kubernetes cluster, use the
[sysbox-deploy-k8s](install-k8s.md) daemonset instead.**

Also, if you need to build and install Sysbox from source (e.g., to get the latest
upstream code or because there is no Sysbox package for your Linux distro),
see the [Sysbox developer's guide](../developers-guide/README.md).

## Contents

-   [Available Sysbox Packages](#available-sysbox-packages)
-   [Host Requirements](#host-requirements)
-   [Installing Sysbox](#installing-sysbox)
-   [Installing Sysbox Enterprise Edition (Sysbox-EE)](#installing-sysbox-enterprise-edition-sysbox-ee)
-   [Installing Shiftfs](#installing-shiftfs)
-   [Miscellaneous Installation Info](#miscellaneous-installation-info)
-   [Uninstallation](#uninstallion)
-   [Upgrading Sysbox or Sysbox Enterprise](#upgrading-sysbox-or-sysbox-enterprise)
-   [Replacing Sysbox with Sysbox Enterprise](#replacing-sysbox-with-sysbox-enterprise)

## Available Sysbox Packages

We are currently offering the [Sysbox packages](https://github.com/nestybox/sysbox/releases) for Ubuntu and Debian distributions.

This means that for other distros you must [build and install Sysbox from source](https://github.com/nestybox/sysbox/blob/master/docs/developers-guide/build.md).

We are working on creating packaged versions for the other supported distros, and
expect to have them soon (ETA winter 2022).

## Host Requirements

The Linux host on which Sysbox runs must meet the following requirements:

1.  It must have one of the [supported Linux distros](../distro-compat.md).

2.  Systemd must be the system's process-manager (the default in the supported distros).

3.  Preferably (though it's not required) the kernel should carry the `shiftfs`
    module.

    -   This module is included by default in Ubuntu desktop and server images,
        but is generally not present in Ubuntu-based cloud VMs and in other
        distros.

    -   When the module is not present, it's possible (and easy) to build it and
        install it. But this only applies to Ubuntu, Debian, and Flatcar hosts.
        See [here](#installing-shiftfs) for info on how to do this.

    -   If shiftfs is not present or supported on your host, using Sysbox requires
        Docker to be configured in "userns-remap mode". The Sysbox installer can
        do this configuration if you so desire (it will ask you for permission
        during installation). See [below](#docker-runtime-configuration) for
        details.

## Installing Sysbox

**NOTE**: if you have a prior version of Sysbox already installed, please
[uninstall it](#uninstallation) first and then follow
the installation instructions below.

1.  Download the latest Sysbox package from the [release](https://github.com/nestybox/sysbox/releases) page.

2.  Verify that the checksum of the downloaded file fully matches the
    expected/published one. For example:

```console
$ sha256sum sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb
b189602cdb2bbca9a1f25159a6e664ebd251d7c2fb6be968c7148564e96744c4  sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb
```

3.  If Docker is running on the host, stop and remove all running Docker containers:

```console
$ docker rm $(docker ps -a -q) -f
```

(if an error is returned, it simply indicates that no existing containers were found).

This is necessary because the Sysbox installer may need to configure and restart
Docker (to make Docker aware of Sysbox). It's possible to avoid the Docker restart;
see [Installing Sysbox w/o Docker restart](#installing-sysbox-without-restarting-docker)
below for more on this.

4.  Install the Sysbox package and follow the installer instructions:

```console
$ sudo apt-get install ./sysbox-ce_0.4.0-0.ubuntu-focal_amd64.deb
```

5.  Verify that Sysbox's Systemd units have been properly installed, and
    associated daemons are properly running:

```console
$ sudo systemctl status sysbox -n20
● sysbox.service - Sysbox container runtime
     Loaded: loaded (/lib/systemd/system/sysbox.service; enabled; vendor preset: enabled)
     Active: active (running) since Sat 2021-07-17 20:32:39 EDT; 23s ago
       Docs: https://github.com/nestybox/sysbox
   Main PID: 2917387 (sh)
      Tasks: 2 (limit: 9484)
     Memory: 756.0K
     CGroup: /system.slice/sysbox.service
             ├─2917387 /bin/sh -c /usr/bin/sysbox-runc --version && /usr/bin/sysbox-mgr --version && /usr/bin/sysbox-fs --version && /bin/sleep infinity
             └─2917423 /bin/sleep infinity

Jul 17 20:32:39 dev-vm1 systemd[1]: Started Sysbox container runtime.
Jul 17 20:32:39 dev-vm1 sh[2917388]: sysbox-runc
Jul 17 20:32:39 dev-vm1 sh[2917388]:         edition:         Community Edition (CE)
Jul 17 20:32:39 dev-vm1 sh[2917388]:         version:         0.4.0
Jul 17 20:32:39 dev-vm1 sh[2917388]:         commit:         9e55c35e249f753c7d31e987c21d4ca4a2ddacfb
Jul 17 20:32:39 dev-vm1 sh[2917388]:         built at:         Tue Jul 13 18:38:39 UTC 2021
Jul 17 20:32:39 dev-vm1 sh[2917388]:         built by:         Rodny Molina
Jul 17 20:32:39 dev-vm1 sh[2917388]:         oci-specs:         1.0.2-dev
Jul 17 20:32:39 dev-vm1 sh[2917395]: sysbox-mgr
Jul 17 20:32:39 dev-vm1 sh[2917395]:         edition:         Community Edition (CE)
Jul 17 20:32:39 dev-vm1 sh[2917395]:         version:         0.4.0
Jul 17 20:32:39 dev-vm1 sh[2917395]:         commit:         8b13c261d1eb3a7a0c632b7f13c3cd19a447d14b
Jul 17 20:32:39 dev-vm1 sh[2917395]:         built at:         Tue Jul 13 18:39:19 UTC 2021
Jul 17 20:32:39 dev-vm1 sh[2917395]:         built by:         Rodny Molina
Jul 17 20:32:40 dev-vm1 sh[2917400]: sysbox-fs
Jul 17 20:32:40 dev-vm1 sh[2917400]:         edition:         Community Edition (CE)
Jul 17 20:32:40 dev-vm1 sh[2917400]:         version:         0.4.0
Jul 17 20:32:40 dev-vm1 sh[2917400]:         commit:         394d51110fe23bd64b7be8fb9b217dc9cff16032
Jul 17 20:32:40 dev-vm1 sh[2917400]:         built at:         Tue Jul 13 18:39:04 UTC 2021
Jul 17 20:32:40 dev-vm1 sh[2917400]:
```

This indicates all Sysbox components are running properly. If you are curious on
what these are, refer to the [design section](design.md).

After you've installed Sysbox, you can now use it to deploy containers with
Docker. See the [Quickstart Guide](../quickstart/README.md) for examples.

If you hit problems during installation, see the [Troubleshooting doc](troubleshoot.md).

## Installing Sysbox Enterprise Edition (Sysbox-EE)

Sysbox Enterprise Edition (Sysbox-EE) is the enterprise version of Sysbox, with
improved security, functionality, performance, life-cycle, and Nestybox support.

The installation for Sysbox Enterprise Edition (Sysbox-EE) is exactly the same
as for Sysbox (see [prior section](#installing-sysbox)), except you use the
Sysbox-EE installation package found in the [Sysbox-EE repo](https://github.com/nestybox/sysbox-ee).

For example, to install Sysbox-EE on a Ubuntu Focal host:

```console
$ wget https://github.com/nestybox/sysbox-ee/releases/download/v0.4.0/sysbox-ee_0.4.0-0.ubuntu-focal_amd64.deb

$ sudo apt-get install ./sysbox-ee_0.4.0-0.ubuntu-focal_amd64.deb

$ sudo systemctl status sysbox -n20
● sysbox.service - Sysbox container runtime
     Loaded: loaded (/lib/systemd/system/sysbox.service; enabled; vendor preset: enabled)
     Active: active (running) since Tue 2021-07-20 19:35:31 UTC; 18s ago
       Docs: https://github.com/nestybox/sysbox
   Main PID: 7963 (sh)
      Tasks: 2 (limit: 4617)
     Memory: 868.0K
     CGroup: /system.slice/sysbox.service
             ├─7963 /bin/sh -c /usr/bin/sysbox-runc --version && /usr/bin/sysbox-mgr --version && /usr/bin/sysbox-fs --version && /bin/sleep infinity
             └─7986 /bin/sleep infinity

Jul 20 19:35:31 focal systemd[1]: Started Sysbox container runtime.
Jul 20 19:35:32 focal sh[7965]: sysbox-runc
Jul 20 19:35:32 focal sh[7965]:         edition:         Enterprise Edition (EE)
Jul 20 19:35:32 focal sh[7965]:         version:         0.4.0
Jul 20 19:35:32 focal sh[7965]:         commit:         f4daa007da10280095911dde80a8cb95d03c4859
Jul 20 19:35:32 focal sh[7965]:         built at:         Mon Jul 19 18:55:14 UTC 2021
Jul 20 19:35:32 focal sh[7965]:         built by:         Rodny Molina
Jul 20 19:35:32 focal sh[7965]:         oci-specs:         1.0.2-dev
Jul 20 19:35:32 focal sh[7972]: sysbox-mgr
Jul 20 19:35:32 focal sh[7972]:         edition:         Enterprise Edition (EE)
Jul 20 19:35:32 focal sh[7972]:         version:         0.4.0
Jul 20 19:35:32 focal sh[7972]:         commit:         de7cbb47c9a667d4aaa79e4ca8aeadf6d5124bb2
Jul 20 19:35:32 focal sh[7972]:         built at:         Mon Jul 19 18:55:51 UTC 2021
Jul 20 19:35:32 focal sh[7972]:         built by:         Rodny Molina
Jul 20 19:35:32 focal sh[7978]: sysbox-fs
Jul 20 19:35:32 focal sh[7978]:         edition:         Enterprise Edition (EE)
Jul 20 19:35:32 focal sh[7978]:         version:         0.4.0
Jul 20 19:35:32 focal sh[7978]:         commit:         b0cb35cf449f5c929dba24fc940aef151f4432c5
Jul 20 19:35:32 focal sh[7978]:         built at:         Mon Jul 19 18:55:37 UTC 2021
Jul 20 19:35:32 focal sh[7978]:         built by:         Rodny Molina
```

After you've installed Sysbox-EE, you can now use it to deploy containers with
Docker. See the [Quickstart Guide](../quickstart/README.md) for examples.

**NOTE:** either Sysbox or Sysbox Enterprise must be installed on a given host,
never both.

## Installing Shiftfs

Sysbox works best when the `shiftfs` module is present in the Linux kernel.

This module is included by default in Ubuntu desktop and server images, but generally
not included in Ubuntu-based cloud VMs and other Linux distros.

For hosts where shiftfs is not included, it's possible (and fairly easy) to
build and install it.

**NOTE: Shiftfs is currently supported on Ubuntu, Debian, and Flatcar. For other distros
(e.g., Fedora, CentOS) using Sysbox requires that Docker be configured in userns-remap
mode (see [below](#docker-userns-remap)).**

To build and install shiftfs, follow the instructions here: https://github.com/toby63/shiftfs-dkms

For example, to install shiftfs on a Ubuntu-based cloud VM with Linux 5.8,
follow these simple steps:

```console
git clone -b k5.8 https://github.com/toby63/shiftfs-dkms.git shiftfs-k58
cd shiftfs-k58
./update1
sudo make -f Makefile.dkms
modinfo shiftfs
```

Note that you'll need to install the `git`, `make`, `dkms`, `wget`, and
kernel-header packages in order to perform the shiftfs build.

In the near future (kernels 5.12+), shiftfs is expected to be replaced with a
more generic kernel mechanism for filesystem user-ID mappings that will be
supported across all distros. Sysbox will soon have support for this.

## Miscellaneous Installation Info

### Docker Runtime Configuration

During installation, the Sysbox installer will detect if Docker is running and
reconfigure the Docker daemon such that it detects the Sysbox runtime. It does
this by adding the following configuration to `/etc/docker/daemon.json` and
sending a signal (SIGHUP) to Docker:

```json
{
   "runtimes": {
      "sysbox-runc": {
         "path": "/usr/bin/sysbox-runc"
      }
   }
}
```

If all is well, Docker will recognize the Sysbox runtime:

```console
$ docker info | grep -i runtime
WARNING: No swap limit support
 Runtimes: runc sysbox-runc
  Default Runtime: runc
```

### Docker Userns-Remap

During installation, the Sysbox installer will also check if Docker needs to be placed
in [userns-remap mode](https://docs.docker.com/engine/security/userns-remap/) or not.

The installer uses the following logic:

-   If the kernel carries the `shiftfs` module, then Docker does not need to be
    placed in userns-remap mode.

-   Otherwise, Docker needs to be placed in userns-remap mode to work with Sysbox.

If Docker needs to be placed in userns-remap, the Sysbox installer will check if
Docker is already in this mode (by looking for `userns-remap` in
`/etc/docker/daemon.json` and `userns` entry in `docker info` output). If so, no further
action is required.

Otherwise, the Sysbox installer will ask the user for permission to transition Docker
into `userns-remap` mode. If user responds affirmatively, Sysbox installer will make
the required changes (see below) and restart Docker automatically. Otherwise, the user
will need to make these changes manually and restart Docker service afterwards (e.g.,
`systemctl restart docker`)

```console
{
   "userns-remap": "sysbox",
   "runtimes": {
       "sysbox-runc": {
          "path": "/usr/bin/sysbox-runc"
       }
   }
}
```

When Docker is placed in userns-remap mode, there are a couple of caveats to
keep in mind:

-   Configuring Docker this way places a few functional limitations on regular
    Docker containers (those launched with Docker's default `runc`), as described
    in this [Docker document](https://docs.docker.com/engine/security/userns-remap).

-   Bind-mounting host files or directories to the container requires users
    to [manually configure file permissions](storage.md#host-does-not-support-user-and-group-id-shifting-ie-no-shiftfs).

### Configuring Docker's Default Runtime to Sysbox

If you wish to make Sysbox the default runtime for Docker, you must reconfigure
Docker manually (the Sysbox installer won't do this).

To do so, add the `default-runtime` config to `/etc/docker/daemon.json`. It
should look similar to this:

    {
      "default-runtime": "sysbox-runc",
      "runtimes": {
         "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
         }
      }
    }

Then restart Docker (e.g., `sudo systemctl restart docker`). With this setup,
you can omit the `--runtime=sysbox-runc` flag when using `docker run` to create
containers with Sysbox.

### Installing Sysbox without Restarting Docker

To simplify the Sysbox installation process, we explicitly ask the user to stop and remove
the existing containers.

However, this may not be a feasible option in production scenarios. This section
tackles this problem by enumerating the docker configuration elements that can
be pre-configured to allow Sysbox installation to succeed without impacting the
existing containers.

During Sysbox installation, the installer adds the following attributes into
Docker's configuration file if these are not already present. With the exception
of the `runtime` attribute, all others require a Docker process restart for
changes to be digested by the Docker engine.

-   `runtime` -- sysbox-runc must be added as a new runtime.
-   `bip` -- explicitly sets docker's interface (docker0) network IP address.
-   `default-address-pools` -- explicitly defines the subnets to be utilized by Docker
    for custom-networks purposes.
-   `userns-remap` -- activates 'userns-remap' mode (only required in scenarios without
    'shiftfs' module, see [Docker Userns-Remap](#Docker-Userns-Remap) section above).

To prevent Sysbox installer from restarting Docker daemon during the installation process,
the Docker engine must be already aware of these required attributes, and for this to
happen, Docker configuration files such as the following ones should be in placed
in `/etc/docker/daemon.json`:

-   "shiftfs" scenario

```yaml
{
    "bip": "172.24.0.1/16",
    "default-address-pools": [
        {
            "base": "172.31.0.0/16",
            "size": 24
        }
    ]
}
```

-   "userns-remap" scenario

```yaml
{
    "userns-remap": "sysbox",
    "bip": "172.24.0.1/16",
    "default-address-pools": [
        {
            "base": "172.31.0.0/16",
            "size": 24
        }
    ]
}
```

Notice that it is up to the user to decide which specific `bip` or
`default-address-pools` values/ranges are pre-configured, and the same applies
to the `userns-remap` entry. The Sysbox installer will not restart Docker as
long as there's one instance of these must-have attributes in Docker's
`/etc/docker/daemon.json` configuration file.

### Avoiding the Docker Snap Package

Ubuntu offers two methods for installing Docker:

1.  Via `apt get` (aka native installation)

2.  Via `snap install` (aka snappy installation)

In recent versions of Ubuntu, (2) is the default approach. For example, while installing
Ubuntu Focal on a VM, the installer will ask if you want to install Docker. If you answer
"yes", it will use the snappy installation method.

You can tell if Docker is installed via a snap by doing:

```console
$ which docker
/snap/bin/docker
```

Unfortunately, Sysbox **does not currently support** working with Docker when the latter is
installed via a snap package.

In the meantime, you **must install Docker natively** (method (1) above).

These are the steps to do so:

1.  If Docker is installed via a snap, remove the snap:

```console
$ sudo snap remove docker
docker removed
```

2.  Install Docker natively.

Follow the instructions in this [Docker doc](https://docs.docker.com/engine/install/ubuntu/).

3.  Confirm Docker is installed natively:

```console
$ which docker
/usr/bin/docker
```

4.  Make sure you are in the `docker` group:

```console
$ sudo usermod -a -G docker $(whoami)
```

You may need to log-out and log-in for the group setting to take effect.

If you are not in the `docker` group (or have no sudo privileges), you'll see an error such as:

```console
$ docker run -it alpine
Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: ... connect: permission denied
```

5.  Verify Docker works:

```console
$ docker run -it alpine
Unable to find image 'alpine:latest' locally
latest: Pulling from library/alpine
df20fa9351a1: Pull complete
Digest: sha256:185518070891758909c9f839cf4ca393ee977ac378609f700f60a771a2dfe321
Status: Downloaded newer image for alpine:latest
/ #
```

At this point you have Docker working, and can now [install Sysbox](#installing-sysbox).

If you want to revert back to the Docker snap, the steps are below, but keep in
mind that Sysbox **won't work**.

1.  Uninstall the native Docker

See [here](https://docs.docker.com/engine/install/ubuntu/#uninstall-old-versions).

2.  Re-install the Docker snap:

```console
$ sudo snap install docker
```

## Uninstallation

Prior to uninstalling Sysbox, make sure all system containers are removed.
There is a simple shell script to do this [here](../../scr/rm_all_syscont).

1.  Uninstall Sysbox binaries plus all the associated configuration and Systemd
    files:

```console
$ sudo apt-get purge sysbox-ce -y
```

For Sysbox Enterprise:

```console
$ sudo apt-get purge sysbox-ee -y
```

2.  Remove the `sysbox` user from the system:

```console
$ sudo userdel sysbox
```

## Upgrading Sysbox or Sysbox Enterprise

To upgrade Sysbox, first uninstall Sysbox and re-install the updated version.

You can find the latest versions of Sysbox here:

-   [Sysbox Community Edition Releases](https://github.com/nestybox/sysbox/releases/tag/v0.4.0).
-   [Sysbox Enterprise Edition Releases](https://github.com/nestybox/sysbox-ee/releases/tag/v0.4.0).

Note that you must stop all Sysbox containers on the host prior to uninstalling
Sysbox.

During the uninstall and re-install process, the Sysbox installer will restart
Docker if needed.

## Replacing Sysbox with Sysbox Enterprise

Sysbox Enterprise Edition (Sysbox-EE) is a drop-in replacement for Sysbox.

If you have a host with Sysbox and wish to install Sysbox Enterprise in it,
simply [uninstall Sysbox](#uninstallation) and
[install Sysbox Enterprise](#installing-sysbox-enterprise-edition-sysbox-ee)
as described above.

**NOTE:** either Sysbox or Sysbox Enterprise must be installed on a given host,
never both.
