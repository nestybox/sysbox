# Sysbox Developer's Guide: Building & Installing

## Contents

-   [Host Requirements](#host-requirements)
-   [Cloning the Sysbox Repo](#cloning-the-sysbox-repo)
-   [The Sysbox Makefile](#the-sysbox-makefile)
-   [Building & Installing from Source](#building--installing-from-source)
-   [Starting Sysbox](#starting-sysbox)
-   [Configuring Docker](#configuring-docker)
-   [Using Sysbox](#using-sysbox)
-   [Cleanup & Uninstall](#cleanup--uninstall)
-   [Docker Installation](#docker-installation)

## Host Requirements

In order to build Sysbox, the Linux host on which you work must meet the
following requirements:

1) It must have one of the [supported Linux distros](../distro-compat.md).

-   For local development and testing purposes, you can build Sysbox in any of
the [supported distributions](docs/distro-compat.md). However, if you are
planning to contribute to Sysbox's public repositories, you should then have a
distro that carries the `shiftfs` module (e.g. Ubuntu Server versions for Bionic
or Focal) so that you can properly test your changes with and without `shiftfs`.

2) Docker must be installed natively (i.e., **not** with the Docker snap package).

-   See [below](#docker-installation) if you have a Docker snap installation and
    need to change it to a native installation.

## Cloning the Sysbox Repo

Clone the repo with:

```
git clone --recursive git@github.com:nestybox/sysbox.git
```

Sysbox uses Go modules, so you should clone this into a directory that is
outside your $GOPATH.

In case of authentication error, make sure your setup is properly configured
to allow ssh connectivity to Github. Refer to [this](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh)
doc for details. Or make git use `https` instead of `ssh` by configuring `git config --global url.https://github.com/.insteadOf git@github.com:`.

## The Sysbox Makefile

The sysbox Makefile has a bunch of targets to build, install, and test
Sysbox. Type `make` to see all the make targets:

```
$ make

Usage:
  make <target>

  Building targets
    sysbox                  Build sysbox (the build occurs inside a container, so the host is not polluted)
    sysbox-debug            Build sysbox (with debug symbols)
    sysbox-static           Build sysbox (static linking)

  Installation targets
    install                 Install all sysbox binaries (requires root privileges)
    uninstall               Uninstall all sysbox binaries (requires root privileges)

  Testing targets
    test                    Run all sysbox test suites
    test-sysbox             Run sysbox integration tests
    ...

  Sysbox-In-Docker targets
    sysbox-in-docker        Build sysbox-in-docker sandbox image
    test-sind               Run the sysbox-in-docker integration tests
    ...

  Code Hygiene targets
    lint                    Runs lint checker on sysbox source code and tests
    shfmt                   Formats shell scripts in the repo; requires shfmt.

  Cleaning targets
    clean                   Eliminate sysbox binaries
    clean-libseccomp        Clean libseccomp
    clean-sysbox-in-docker  Clean sysbox-in-docker
```

## Building & Installing from Source

Build Sysbox with:

```
$ make sysbox
```

This target creates a temporary container and builds the binaries for the Sysbox
components inside that container. The resulting binaries are then placed in the
sysbox-fs, sysbox-mgr, and sysbox-runc sub-directories.

Once you've built Sysbox, you install it with:

```
$ sudo make install
```

This last target simply copies the Sysbox binaries to your machine's
`/usr/bin` directory; we don't have a package installer for Sysbox
(unlike the Sysbox version distributed by Nestybox).

## Starting Sysbox

Once Sysbox is installed, you start it with:

```
$ sudo ./scr/sysbox
```

This script starts the sysbox-fs and sysbox-mgr daemons. The daemons will log into
`/var/log/sysbox-fs.log` and `/var/log/sysbox-mgr.log` (these logs are useful
for troubleshooting).

If you wish to start Sysbox with debug logging, use `sudo ./scr/sysbox --debug`.
This slows down Sysbox but it's useful for diagnosing problems.

## Configuring Docker

If you plan to use Docker to deploy system containers with Sysbox, you
must first configure Docker so that it becomes aware of Sysbox.

We suggest you do this by using the convenience script `docker-cfg` located in
the `scr` directory of the Sysbox repo. For example, to configure Docker such
that it's ready to use Sysbox, type:

```
$ sudo ./scr/docker-cfg --sysbox-runtime=enable
```

This will add the sysbox-runtime in the `/etc/docker/daemon.json` as follows:

```json
{
   "runtimes": {
       "sysbox-runc": {
          "path": "/usr/bin/sysbox-runc"
       }
   }
}
```

The script will also configure Docker networking to avoid conflicts between
host and inner container subnets, and will restart Docker (unless it's told
not to).

This script takes several other configuration options, and you can use it to
configure Docker with userns-remap mode (e.g., to use Sysbox in hosts where
shiftfs is not available), to set the default runtime to Sysbox, to output the
config without actually applying it, and several other options. Type
`docker-cfg --help` for more info.

If you don't wish to use the script, then you will have to manually modify
the `/etc/docker/daemon.json` file and restart Docker yourself (e.g.,
`systemctl restart docker`).

## Using Sysbox

After you've installed Sysbox and setup Docker's runtime configuration, you
deploy a system container by simply passing the `--runtime=sysbox-runc` flag to
Docker:

```
$ docker run --runtime=sysbox-runc --rm -it --hostname my_cont debian:latest
```

If all is well, the container will start. You can tell it's a system container
if you see `sysboxfs` mounts inside of it:

```
root@my_cont:/# findmnt | grep sysboxfs
| `-/sys/module/nf_conntrack/parameters/hashsize             sysboxfs[/sys/module/nf_conntrack/parameters/hashsize]                                                    fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
| |-/proc/swaps                                              sysboxfs[/proc/swaps]                                                                                     fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
| |-/proc/sys                                                sysboxfs[/proc/sys]                                                                                       fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
| `-/proc/uptime                                             sysboxfs[/proc/uptime]                                                                                    fuse     rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
```

In addition, the sysbox-fs and sysbox-mgr logs should show activity:

```
$ sudo cat /var/log/sysbox-mgr.log
INFO[2020-08-04 17:09:12] Starting ...
INFO[2020-08-04 17:09:13] Sys container DNS aliasing enabled.
INFO[2020-08-04 17:09:13] Listening on /run/sysbox/sysmgr.sock
INFO[2020-08-04 17:09:13] Ready ...
INFO[2020-08-04 19:48:45] registered new container 181c14fa5ae7d7e38b8113f68e5912be47a5a89ac06a9e283f59742ca7ac130d
```

Refer to the [Sysbox Quickstart Guide](../quickstart/README.md) for examples on how
to use Sysbox.

If you run into problems, refer to the Sysbox [troubleshooting guide](../user-guide/troubleshoot.md).

## Cleanup & Uninstall

```
$ sudo make uninstall
$ make clean
```

## Docker Installation

Ubuntu offers two methods for installing Docker:

1) Via `apt get` (aka native installation)

2) Via `snap install` (aka snappy installation)

In recent versions of Ubuntu, (2) is the default approach. For example, while
installing Ubuntu Focal on a VM, the Ubuntu installer will ask if you want to
install Docker. If you answer "yes", it will use the snappy installation method.

You can tell if Docker is installed via a snap by doing:

```console
$ which docker
/snap/bin/docker
```

Unfortunately, Sysbox **does not currently support** working with Docker when the latter is
installed via a snap package.

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
