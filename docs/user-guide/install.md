# Sysbox User Guide: Installation

## Contents

-   [Host Requirements](#host-requirements)
-   [Installing Sysbox](#installing-sysbox)
-   [Uninstalling Sysbox](#uninstalling-sysbox)
-   [Docker Installation](#docker-installation)

## Host Requirements

The Linux host on which Sysbox runs must meet the following requirements:

1) It must have one of the [supported Linux distros](../distro-compat.md).

2) Systemd must be the system's process-manager (the default in the supported distros).

3) Docker must be installed natively (i.e., **not** with the Docker snap package).

-   See [below](#docker-installation) if you have a Docker snap installation and
    need to change it to a native installation.

## Installing Sysbox

**NOTE**: if you have a prior version of Sysbox already installed, please [uninstall it](#uninstalling-sysbox) first and then follow the installation instructions below.

1) Download the latest Sysbox package from the [release](https://github.com/nestybox/sysbox-external/releases) page.

2) Verify that the checksum of the downloaded file fully matches the expected/published one.
   For example:

```console
$ sha256sum sysbox_0.2.0-0.ubuntu-focal_amd64.deb
736dba5645549ac0aabe11f29c6410bdbb76e717431a8a241833f20ce8b58a11  sysbox_0.2.0-0.ubuntu-focal_amd64.deb
```

3) In scenarios where kernel carries `shiftfs` module, there is no need to stop
and eliminate existing containers prior to Sysbox installation. Sysbox's installer
will seamlessly complete the installation process without service disruption.

   On the other hand, if `shiftfs` module is missing, Sysbox installer may require
   a Docker Service restart. In this scenario (see [userns-remap](#docker-userns-remap) mode), if Docker is not already operating in
   `userns-remap` mode, we encourage users to stop and remove existing containers
   before launching the Sysbox installer:

```
$ docker stop $(docker ps -a -q) && docker container prune -f
```

   If an error is returned, it simply indicates that no existing containers were
   found.

4) Install the Sysbox package and follow the installer instructions:

```console
$ sudo apt-get install ./sysbox_0.2.0-0.ubuntu-focal_amd64.deb -y
```

5) Verify that Sysbox's Systemd units have been properly installed, and
   associated daemons are properly running:

```console
$ systemctl list-units -t service --all | grep sysbox
sysbox-fs.service                   loaded    active   running sysbox-fs component
sysbox-mgr.service                  loaded    active   running sysbox-mgr component
sysbox.service                     loaded    active   exited  Sysbox General Service
```

Note: the sysbox.service is ephemeral (it exits once it launches the other sysbox services; that's why
you see `sysbox.service   loaded  active  exited` above).

After you've installed Sysbox, you can now use it to deploy containers that can
run systemd, Docker, and Kubernetes inside of them seamlessly. See the
[Quickstart Guide](../quickstart/README.md) for examples.

If you are curious on what the other Sysbox services are, refer to the [design section](design.md).

If you hit problems during installation, see the [Troubleshooting doc](troubleshoot.md).

### Docker Runtime Configuration

During installation, the Sysbox installer will reconfigure the Docker daemon such
that it detects the Sysbox runtime. It does this by adding the following
configuration to `/etc/docker/daemon.json` and sending a signal (SIGHUP) to Docker:

```json
{
   "runtimes": {
      "sysbox-runc": {
         "path": "/usr/local/sbin/sysbox-runc"
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

-   If the kernel carries a module called `shiftfs`, then Docker does not need to be
    placed in userns-remap mode.

    -   This is normally the case for the Ubuntu desktop and server editions.

-   Otherwise, Docker does need to be placed in userns-remap mode.

    -   This is likely the case for Ubuntu cloud editions.

If Docker needs to be placed in userns-remap, the Sysbox installer will check if
Docker is already in this mode (by looking for `userns-remap` in
`/etc/docker/daemon.json` and `userns` entry in `docker info` output). If so, no further action is required.

Otherwise, the Sysbox installer will add the following `userns-remap` entry to the
`/etc/docker/daemon.json` file:

```console
{
   "userns-remap": "sysbox",
   "runtimes": {
       "sysbox-runc": {
          "path": "/usr/local/sbin/sysbox-runc"
       }
   }
}
```

The installer will then ask the user if Docker should be restarted. If the user
responds affirmatively, the installer will restart Docker
automatically. Otherwise, the user will need to restart Docker manually (e.g.,
`systemctl restart docker`) before using Sysbox.

When Docker is placed in userns-remap mode, there are a couple of caveats to
keep in mind:

-   Configuring Docker this way places a few functional limitations on regular
    Docker containers (those launched with Docker's default `runc`), as described
    in this [Docker document](https://docs.docker.com/engine/security/userns-remap).

-   System container isolation, while strong, is reduced compared to using
    `shiftfs`. That's because userns-remap causes Docker to put Sysbox into
    "Directed Userns ID Mapping" mode. See [here](security.md#user-namespace-id-mapping)
    for more info on this.

## Uninstalling Sysbox

Prior to uninstalling Sysbox, make sure all system containers are removed.
There is a simple shell script to do this [here](../../scr/rm_all_syscont).

1) Uninstall Sysbox binaries plus all the associated configuration and Systemd
files:

```console
$ sudo apt-get purge sysbox -y
```

2) Remove the `sysbox` user from the system:

```console
$ sudo userdel sysbox
```

## Docker Installation

Ubuntu offers two methods for installing Docker:

1) Via `apt get` (aka native installation)

2) Via `snap install` (aka snappy installation)

In recent versions of Ubuntu, (2) is the default approach. For example, while installing
Ubuntu Focal on a VM, the installer will ask if you want to install Docker. If you answer
"yes", it will use the snappy installation method.

You can tell if Docker is installed via a snap by doing:

```console
$ which docker
/snap/bin/docker
```

Unfortunately, Sysbox **does not currently support** working with Docker when the latter is
installed via a snap package. We are working on resolving this.

In the meantime, you **must install Docker natively** (method (1) above).

These are the steps to do so:

1) If Docker is installed via a snap, remove the snap:

```console
$ sudo snap remove docker
docker removed
```

2) Install Docker natively.

Follow the instructions in this [Docker doc](https://docs.docker.com/engine/install/ubuntu/).

3) Confirm Docker is installed natively:

```console
$ which docker
/usr/bin/docker
```

4) Make sure you are in the `docker` group:

```console
$ sudo usermod -a -G docker $(whoami)
```

You may need to log-out and log-in for the group setting to take effect.

If you are not in the `docker` group (or have no sudo privileges), you'll see an error such as:

```console
$ docker run -it alpine
Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: ... connect: permission denied
```

5) Verify Docker works:

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

1) Uninstall the native Docker

See [here](https://docs.docker.com/engine/install/ubuntu/#uninstall-old-versions).

2) Re-install the Docker snap:

```console
$ sudo snap install docker
```
