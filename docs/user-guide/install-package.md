# Sysbox User Guide: Installation with the Sysbox Package

This document describes how to install Sysbox using the [packaged versions](https://github.com/nestybox/sysbox/releases).

This is usually the case when installing Sysbox on hosts that have Docker in
them.

**NOTE: If you are installing Sysbox on a Kubernetes cluster, use the
[sysbox-deploy-k8s](install-k8s.md) daemonset instead.**

Also, if you need to build and install Sysbox from source (e.g., to get the latest
upstream code or because there is no Sysbox package for your Linux distro yet),
see the [Sysbox developer's guide](../developers-guide/README.md).

## Contents

- [Sysbox User Guide: Installation with the Sysbox Package](#sysbox-user-guide-installation-with-the-sysbox-package)
  - [Contents](#contents)
  - [Available Sysbox Packages](#available-sysbox-packages)
  - [Host Requirements](#host-requirements)
  - [Installing Sysbox](#installing-sysbox)
  - [Installing Sysbox Enterprise Edition (Sysbox-EE)](#installing-sysbox-enterprise-edition-sysbox-ee)
  - [Installing Shiftfs](#installing-shiftfs)
  - [Miscellaneous Installation Info](#miscellaneous-installation-info)
    - [Docker Runtime Configuration](#docker-runtime-configuration)
    - [Docker Userns-Remap](#docker-userns-remap)
    - [Configuring Docker's Default Runtime to Sysbox](#configuring-dockers-default-runtime-to-sysbox)
    - [Installing Sysbox without Restarting Docker](#installing-sysbox-without-restarting-docker)
    - [Avoiding the Docker Snap Package](#avoiding-the-docker-snap-package)
  - [Uninstallation](#uninstallation)
  - [Upgrading Sysbox or Sysbox Enterprise](#upgrading-sysbox-or-sysbox-enterprise)
  - [Replacing Sysbox with Sysbox Enterprise](#replacing-sysbox-with-sysbox-enterprise)

## Available Sysbox Packages

We are currently offering the [Sysbox packages](https://github.com/nestybox/sysbox/releases) for Ubuntu and Debian distributions.

This means that for other distros you must [build and install Sysbox from source](https://github.com/nestybox/sysbox/blob/master/docs/developers-guide/build.md).

We are working on creating packaged versions for the other supported distros, and
expect to have them soon (ETA spring 2022).

## Host Requirements

The Linux host on which Sysbox runs must meet the following requirements:

1.  It must have one of the [supported Linux distros](../distro-compat.md).

2.  Systemd must be the host's process-manager (the default in the supported distros).

## Installing Sysbox

**NOTE**: if you have a prior version of Sysbox already installed, please
[uninstall it](#uninstallation) first and then follow
the installation instructions below.

1.  Download the latest Sysbox package from the [release](https://github.com/nestybox/sysbox/releases) page:

```
$ wget https://downloads.nestybox.com/sysbox/releases/v0.6.2/sysbox-ce_0.6.2-0.linux_amd64.deb
```

2.  Verify that the checksum of the downloaded file fully matches the
    expected/published one. For example:

```console
$ sha256sum sysbox-ce_0.6.2-0.linux_amd64.deb
fd287f2f3b5a072b62c378f9e1eeeeaa2ccad22bb48cb381d30d8c855c51b401  sysbox-ce_0.6.2-0.linux_amd64.deb
```

3.  If Docker is running on the host, we recommend stopping and removing all
    Docker containers as follows (if an error is returned, it simply indicates
    that no existing containers were found):

```console
$ docker rm $(docker ps -a -q) -f
```

This is recommended because the Sysbox installer may need to configure and
restart Docker (to make Docker aware of Sysbox). For production scenarios, it's
possible to avoid the Docker restart; see [Installing Sysbox w/o Docker restart](#installing-sysbox-without-restarting-docker)
below for more on this.

4.  Install the Sysbox package and follow the installer instructions:

```console
$ sudo apt-get install jq
$ sudo apt-get install ./sysbox-ce_0.6.2-0.linux_amd64.deb
```

NOTE: the `jq` tool is used by the Sysbox installer.

5.  Verify that Sysbox's Systemd units have been properly installed, and
    associated daemons are properly running:

```console
$ sudo systemctl status sysbox -n20
● sysbox.service - Sysbox container runtime
     Loaded: loaded (/lib/systemd/system/sysbox.service; enabled; vendor preset: enabled)
     Active: active (running) since Sun 2023-10-15 13:03:50 PDT; 10s ago
       Docs: https://github.com/nestybox/sysbox
   Main PID: 1549 (sh)
      Tasks: 2 (limit: 9357)
     Memory: 424.0K
        CPU: 18ms
     CGroup: /system.slice/sysbox.service
             ├─1549 /bin/sh -c "/usr/bin/sysbox-runc --version && /usr/bin/sysbox-mgr --version && /usr/bin/sysbox-fs --version && /bin/sleep infinity"
             └─1568 /bin/sleep infinity

Oct 15 13:03:50 xps15 systemd[1]: Started Sysbox container runtime.
Oct 15 13:03:50 xps15 sh[1550]: sysbox-runc
Oct 15 13:03:50 xps15 sh[1550]:         edition:         Community Edition (CE)
Oct 15 13:03:50 xps15 sh[1550]:         version:         0.6.2
Oct 15 13:03:50 xps15 sh[1550]:         commit:          60ca93c783b19c63581e34aa183421ce0b9b26b7
Oct 15 13:03:50 xps15 sh[1550]:         built at:        Mon Jun 12 03:49:19 UTC 2023
Oct 15 13:03:50 xps15 sh[1550]:         built by:        Cesar Talledo
Oct 15 13:03:50 xps15 sh[1550]:         oci-specs:       1.0.2-dev
Oct 15 13:03:50 xps15 sh[1557]: sysbox-mgr
Oct 15 13:03:50 xps15 sh[1557]:         edition:         Community Edition (CE)
Oct 15 13:03:50 xps15 sh[1557]:         version:         0.6.2
Oct 15 13:03:50 xps15 sh[1557]:         commit:          4b5fb1def9abe6a256cfe62bacaf2a7d333d81d2
Oct 15 13:03:50 xps15 sh[1557]:         built at:        Mon Jun 12 03:49:55 UTC 2023
Oct 15 13:03:50 xps15 sh[1557]:         built by:        Cesar Talledo
Oct 15 13:03:50 xps15 sh[1562]: sysbox-fs
Oct 15 13:03:50 xps15 sh[1562]:         edition:         Community Edition (CE)
Oct 15 13:03:50 xps15 sh[1562]:         version:         0.6.2
Oct 15 13:03:50 xps15 sh[1562]:         commit:          30fd49edbd51048fed8b2ad0af327598d30b29eb
Oct 15 13:03:50 xps15 sh[1562]:         built at:        Mon Jun 12 03:49:46 UTC 2023
Oct 15 13:03:50 xps15 sh[1562]:         built by:        Cesar Talledo
```

This indicates all Sysbox components are running properly. If you are curious on
what these are, refer to the [design chapter](design.md).

After you've installed Sysbox, you can now use it to deploy containers with
Docker. See the [Quickstart Guide](../quickstart/README.md) for examples.

If you hit problems during installation, see the [Troubleshooting doc](troubleshoot.md).

## Installing Sysbox Enterprise Edition (Sysbox-EE) [DEPRECATED]

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

Shiftfs is a kernel module that Sysbox uses to ensure host volumes mounted
into the (rootless) container show up with proper user and group IDs.

Installing shiftfs on the host is required when running on hosts with Linux
kernel < 5.12.

Installing shiftfs on hosts with kernel >= 5.12 is not required, but nonetheless
recommended, assuming your Linux distro supports shiftfs (e.g., Ubuntu, Debian,
or Flatcar).

The shiftfs module is included by default in Ubuntu desktop and server images,
but generally not included in Ubuntu-based cloud VMs and other Linux distros.

For Ubuntu/Debian/Flatcar hosts where shiftfs is not included, it's possible
(and fairly easy) to build and install it.

To build and install shiftfs, follow the instructions here:
https://github.com/toby63/shiftfs-dkms

For example, to install shiftfs on an Ubuntu-based cloud VM with Linux kernel
version 5.8 or 5.10, follow these simple steps:

```console
sudo apt-get install -y make dkms git wget
git clone -b k5.10 https://github.com/toby63/shiftfs-dkms.git shiftfs-k510
cd shiftfs-k510
./update1
sudo make -f Makefile.dkms
modinfo shiftfs
```

The last command should show that shiftfs is installed on the host.

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

In versions of Sysbox prior to v0.5.0, using Sysbox required either shiftfs
be installed on the host or alternatively that Docker be configured
in [userns-remap mode](https://docs.docker.com/engine/security/userns-remap/).

Starting with Sysbox v0.5.0, configuring Docker in userns-remap mode is
no longer required, even if the host has no support for shiftfs. However,
without shiftfs, you will need a host with kernel >= 5.12 so that Sysbox
can use the kernel's ID-mapped mounts feature.

Avoiding Docker userns-remap mode is desirable because that mode places a few
[limitations](https://docs.docker.com/engine/security/userns-remap/#user-namespace-known-limitations) on Docker containers.

### Configuring Docker's Default Runtime to Sysbox

In some cases it's desirable to make Sysbox the default container runtime for
Docker (as opposed to the standard runc runtime).

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

To simplify the Sysbox installation process, we explicitly ask the user to stop
and remove the existing containers.

However, this may not be a feasible option in production scenarios. This section
tackles this problem by enumerating the docker configuration elements that can
be preconfigured to allow Sysbox installation to succeed without impacting the
existing containers.

During Sysbox installation, the installer adds the following attributes into
Docker's configuration file if these are not already present. With the exception
of the `runtime` attribute, all others require a Docker process restart for
changes to be digested by the Docker engine.

-   `runtime` -- sysbox-runc must be added as a new runtime.
-   `bip` -- explicitly sets Docker's interface (docker0) network IP address.
-   `default-address-pools` -- explicitly defines the subnets to be utilized by Docker
    for custom-networks purposes.

To prevent Sysbox installer from restarting Docker daemon during the installation process,
the Docker engine must be already aware of these required attributes, and for this to
happen, Docker configuration files such as the following ones should be in placed
in `/etc/docker/daemon.json`:

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

Notice that it is up to the user to decide which specific `bip` or
`default-address-pools` values/ranges are pre-configured. The Sysbox installer
will not restart Docker as long as there's one instance of these "must-have"
attributes in Docker's `/etc/docker/daemon.json` configuration file.

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

Prior to uninstalling Sysbox, make sure all Sysbox containers are removed.
There is a simple shell script to do this [here](../../scr/rm_all_syscont).
Non-Sysbox containers can remain untouched.

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

-   [Sysbox Community Edition Releases](https://github.com/nestybox/sysbox/releases/tag/v0.5.2).
-   [Sysbox Enterprise Edition Releases](https://github.com/nestybox/sysbox-ee/releases/tag/v0.5.2).

Note that you must stop all Sysbox containers on the host prior to uninstalling
Sysbox (see previous section).

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
