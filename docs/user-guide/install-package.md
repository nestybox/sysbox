# Sysbox User Guide: Installation with the Sysbox Package

This document describes how to install Sysbox using the [packaged versions](https://github.com/nestybox/sysbox/releases).

If you are installing Sysbox on a Kubernetes cluster, use the
[sysbox-deploy-k8s](install-k8s.md) daemonset instead.

And if you need to build and install Sysbox from source (e.g., to get the latest
upstream code or because there is no Sysbox package for your Linux distro),
see the [Sysbox developer's guide](../developers-guide/README.md).

## Contents

-   [Host Requirements](#host-requirements)
-   [Installing Sysbox](#installing-sysbox)
-   [Miscellaneous Installation Info](#miscellaneous-installation-info)
-   [Uninstalling Sysbox](#uninstalling-sysbox)

## Available Sysbox Packages

We are currently offering the [Sysbox packages](https://github.com/nestybox/sysbox/releases) for Ubuntu and Debian distributions.

This means that for other distros you must [build and install Sysbox from source](https://github.com/nestybox/sysbox/blob/master/docs/developers-guide/build.md).

We are working on creating packaged versions for the other supported distros, and
expect to have them soon (ETA summer 2021).

## Host Requirements

The Linux host on which Sysbox runs must meet the following requirements:

1.  It must have one of the [supported Linux distros](../distro-compat.md).

2.  Systemd must be the system's process-manager (the default in the supported distros).

## Installing Sysbox

**NOTE**: if you have a prior version of Sysbox already installed, please
[uninstall it](#uninstalling-sysbox) first and then follow the installation
instructions below.

1.  Download the latest Sysbox package from the [release](https://github.com/nestybox/sysbox/releases) page.

2.  Verify that the checksum of the downloaded file fully matches the
    expected/published one. For example:

```console
$ shasum sysbox-ce_0.3.0-0.ubuntu-focal_amd64.deb
4850d18ed2af73f2819820cd8993f9cdc647cc79  sysbox-ce_0.3.0-0.ubuntu-focal_amd64.deb
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
$ sudo apt-get install ./sysbox-ce_0.3.0-0.ubuntu-focal_amd64.deb -y
```

5.  Verify that Sysbox's Systemd units have been properly installed, and
    associated daemons are properly running:

```console
$ sudo systemctl status sysbox -n20

● sysbox.service - Sysbox container runtime
     Loaded: loaded (/lib/systemd/system/sysbox.service; enabled; vendor preset: enabled)
     Active: active (running) since Sat 2021-03-27 00:15:36 EDT; 20s ago
       Docs: https://github.com/nestybox/sysbox
   Main PID: 2305016 (sh)
      Tasks: 2 (limit: 9487)
     Memory: 792.0K
     CGroup: /system.slice/sysbox.service
             ├─2305016 /bin/sh -c /usr/bin/sysbox-runc --version && /usr/bin/sysbox-mgr --version && /usr/bin/sysbox-fs --version && /bin/sleep infinity
             └─2305039 /bin/sleep infinity

Mar 27 00:15:36 dev-vm1 systemd[1]: Started Sysbox container runtime.
Mar 27 00:15:36 dev-vm1 sh[2305018]: sysbox-runc
Mar 27 00:15:36 dev-vm1 sh[2305018]:         edition:         Community Edition (CE)
Mar 27 00:15:36 dev-vm1 sh[2305018]:         version:         0.3.0
Mar 27 00:15:36 dev-vm1 sh[2305018]:         commit:          df952e5276cb6e705e0be331e9a9fe88f372eab8
Mar 27 00:15:36 dev-vm1 sh[2305018]:         built at:         Sat Mar 27 01:34:12 UTC 2021
Mar 27 00:15:36 dev-vm1 sh[2305018]:         built by:         Rodny Molina
Mar 27 00:15:36 dev-vm1 sh[2305018]:         oci-specs:         1.0.2-dev
Mar 27 00:15:36 dev-vm1 sh[2305024]: sysbox-mgr
Mar 27 00:15:36 dev-vm1 sh[2305024]:         edition:         Community Edition (CE)
Mar 27 00:15:36 dev-vm1 sh[2305024]:         version:         0.3.0
Mar 27 00:15:36 dev-vm1 sh[2305024]:         commit:          6ae5668e797ee1bb88fd5f5ae663873a87541ecb
Mar 27 00:15:36 dev-vm1 sh[2305024]:         built at:         Sat Mar 27 01:34:41 UTC 2021
Mar 27 00:15:36 dev-vm1 sh[2305024]:         built by:         Rodny Molina
Mar 27 00:15:36 dev-vm1 sh[2305031]: sysbox-fs
Mar 27 00:15:36 dev-vm1 sh[2305031]:         edition:         Community Edition (CE)
Mar 27 00:15:36 dev-vm1 sh[2305031]:         version:         0.3.0
Mar 27 00:15:36 dev-vm1 sh[2305031]:         commit:          bb001b7fe2a0a234fe86ab20045677470239e248
Mar 27 00:15:36 dev-vm1 sh[2305031]:         built at:         Sat Mar 27 01:34:30 UTC 2021
Mar 27 00:15:36 dev-vm1 sh[2305031]:         built by:         Rodny Molina
$
```

This indicates all Sysbox components are running properly. If you are curious on
what these are, refer to the [design section](design.md).

After you've installed Sysbox, you can now use it to deploy containers with
Docker. See the [Quickstart Guide](../quickstart/README.md) for examples.

If you hit problems during installation, see the [Troubleshooting doc](troubleshoot.md).

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

-   If the kernel carries a module called `shiftfs`, then Docker does not need to be
    placed in userns-remap mode.

    -   This is normally the case for the Ubuntu desktop and server editions. It
        can also be [added](https://github.com/toby63/shiftfs-dkms) to
        Ubuntu cloud server editions which don't carry it by default.

-   Otherwise, Docker does need to be placed in userns-remap mode to work with Sysbox.

    -   This is likely the case for the non-Ubuntu [supported distributions](../distro-compat.md).

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
installed via a snap package. We are working on resolving this.

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

## Uninstalling Sysbox

Prior to uninstalling Sysbox, make sure all system containers are removed.
There is a simple shell script to do this [here](../../scr/rm_all_syscont).

1.  Uninstall Sysbox binaries plus all the associated configuration and Systemd
    files:

```console
$ sudo apt-get purge sysbox -y
```

2.  Remove the `sysbox` user from the system:

```console
$ sudo userdel sysbox
```
