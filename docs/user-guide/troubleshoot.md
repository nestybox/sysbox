# Sysbox User Guide: Troubleshooting

## Contents

-   [Sysbox Installation Problems](#sysbox-installation-problems)
-   [Docker reports Unknown Runtime error](#docker-reports-unknown-runtime-error)
-   [Ubuntu Shiftfs Module Not Present](#ubuntu-shiftfs-module-not-present)
-   [Unprivileged User Namespace Creation Error](#unprivileged-user-namespace-creation-error)
-   [Bind Mount Permissions Error](#bind-mount-permissions-error)
-   [Failed to Setup Docker Volume Manager Error](#failed-to-setup-docker-volume-manager-error)
-   [Failed to register with sysbox-mgr or sysbox-fs](#failed-to-register-with-sysbox-mgr-or-sysbox-fs)
-   [Docker reports failure setting up ptmx](#docker-reports-failure-setting-up-ptmx)
-   [Docker exec fails](#docker-exec-fails)
-   [Sysbox Logs](#sysbox-logs)
-   [The `/var/lib/sysbox` is not empty even though there are no containers](#the-varlibsysbox-is-not-empty-even-though-there-are-no-containers)
-   [Kubernetes-in-Docker fails to create pods](#kubernetes-in-docker-fails-to-create-pods)
-   [Core-Dump generation](#core-dump-generation)

## Sysbox Installation Problems

When installing the Sysbox package with the `dpkg` command
(see the [Installation instructions](../../README.md#installing-sysbox)), the expected output is:

```console
$ sudo dpkg -i sysbox_0.2.0-0.ubuntu-eoan_amd64.deb
Selecting previously unselected package sysbox.
(Reading database ... 155191 files and directories currently installed.)
Preparing to unpack sysbox_0.2.0-0.ubuntu-eoan_amd64.deb ...
Unpacking sysbox (0.1.2-0.ubuntu-eoan) ...
Setting up sysbox (0.1.2-0.ubuntu-eoan) ...
Created symlink /etc/systemd/system/sysbox.service.wants/sysbox-fs.service → /lib/systemd/system/sysbox-fs.service.
Created symlink /etc/systemd/system/sysbox.service.wants/sysbox-mgr.service → /lib/systemd/system/sysbox-mgr.service.
Created symlink /etc/systemd/system/multi-user.target.wants/sysbox.service → /lib/systemd/system/sysbox.service.
```

In case an error occurs during installation as a consequence of a missing
software dependency, proceed to download and install the missing package(s) as
indicated below. Once this requirement is satisfied, Sysbox's installation
process will be automatically re-launched to conclude this task.

Missing dependency output:

```console
...
dpkg: dependency problems prevent configuration of sysbox:
sysbox depends on jq; however:
Package jq is not installed.

dpkg: error processing package sysbox (--install):
dependency problems - leaving unconfigured
Errors were encountered while processing:
sysbox
```

Install missing package by fixing (-f) system's dependency structures.

```console
$ sudo apt-get update
$ sudo apt-get install -f -y
```

Verify that Sysbox's systemd units have been properly installed, and
associated daemons are properly running:

```console
$ systemctl list-units -t service --all | grep sysbox
sysbox-fs.service                   loaded    active   running sysbox-fs component
sysbox-mgr.service                  loaded    active   running sysbox-mgr component
sysbox.service                     loaded    active   exited  Sysbox General Service
```

The sysbox.service is ephemeral (it exits once it launches the other sysbox services),
so the `active exited` status above is expected.

## Docker reports Unknown Runtime error

When creating a system container, Docker may report the following error:

```console
$ docker run --runtime=sysbox-runc -it ubuntu:latest
docker: Error response from daemon: Unknown runtime specified sysbox-runc.
```

This indicates that the Docker daemon is not aware of the Sysbox
runtime.

This is likely due to one of the following reasons:

1) Docker is installed via a Ubuntu snap package.

2) Docker is installed natively, but it's daemon configuration file
   (`/etc/docker/daemon.json`) has an error.

For (1):

At this time, Sysbox does not support Docker installations via snap.
See [host requirements](install.md#host-requirements) for more info
and how to overcome this.

For (2):

The `/etc/docker/daemon.json` file should have an entry for `sysbox-runc` as follows:

```console
{
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
        }
    }
}
```

Double check that this is the case. If not, change the file and restart Docker:

```console
$ sudo systemctl restart docker.service
```

**NOTE:** The Sysbox installer automatically does this configuration and
restarts Docker. Thus this error is uncommon.

## Docker indicates "unable to retrieve OCI runtime error"

When creating a system container, Docker may report the following error:

```
# docker run --runtime=sysbox-runc -it --rm nestybox/alpine-docker
33a50b33f0e23f7ce9c2e42b9c6521d91ab1f833b9b8cd5884d8f32c60dfd144
docker: Error response from daemon: OCI runtime create failed: unable to retrieve OCI runtime error (open /run/containerd/io.containerd.runtime.v1.linux/moby/33a50b33f0e23f7ce9c2e42b9c6521d91ab1f833b9b8cd5884d8f32c60dfd144/log.json: no such file or directory): /usr/bin/sysbox-runc did not terminate successfully: unknown.
```

This can occur is distros such as Fedora and CentOS where `shiftfs` is not
supported.  In such distros, Sysbox requires that Docker be configured with
"userns-remap". If it's not, the error above can occur.

To solve it, please configure Docker with userns-remap as follows:

1) Add the userns-remap line to the `/etc/docker/daemon.json` file as shown below:

```console
# cat /etc/docker/daemon.json
{
   "userns-remap": "sysbox",
   "runtimes": {
      "sysbox-runc": {
         "path": "/usr/bin/sysbox-runc"
      }
   }
}
```

2) Restart the Docker daemon (make sure any running containers are stopped):

```console
# sudo docker stop $(docker ps -aq)
# sudo systemctl restart docker
```

## Ubuntu Shiftfs Module Not Present

When creating a system container, the following error indicates that
the Ubuntu `shiftfs` module is required by Sysbox but it's not loaded
in the Linux kernel:

```console
# docker run --runtime=sysbox-runc -it debian:latest
docker: Error response from daemon: OCI runtime create failed: container requires user-ID shifting but error was found: shiftfs module is not loaded in the kernel. Update your kernel to include shiftfs module or enable Docker with userns-remap. Refer to the Sysbox troubleshooting guide for more info: unknown
```

First, check if shiftfs if present:

```
# lsmod | grep shiftfs
```

If not present, try loading it manually into the kernel:

```
# sudo modprobe shiftfs
```

If you don't have shiftfs, you can try placing Docker in userns-remap mode as
follows:

1) Add the userns-remap line to the `/etc/docker/daemon.json` file as shown below:

```console
# cat /etc/docker/daemon.json
{
   "userns-remap": "sysbox",
   "runtimes": {
      "sysbox-runc": {
         "path": "/usr/bin/sysbox-runc"
      }
   }
}
```

2) Restart the Docker daemon (make sure any running containers are stopped):

```console
# sudo docker stop $(docker ps -aq)
# sudo systemctl restart docker
```

## Unprivileged User Namespace Creation Error

When creating a system container, Docker may report the following error:

```console
docker run --runtime=sysbox-runc -it ubuntu:latest
docker: Error response from daemon: OCI runtime create failed: host is not configured properly: kernel is not configured to allow unprivileged users to create namespaces: /proc/sys/kernel/unprivileged_userns_clone: want 1, have 0: unknown.
```

This means that the host's kernel is not configured to allow unprivileged users
to create user namespaces.

For Ubuntu, fix this with:

```console
sudo sh -c "echo 1 > /proc/sys/kernel/unprivileged_userns_clone"
```

**Note:** The Sysbox package installer automatically executes this
instruction, so normally there is no need to do this configuration
manually.

## Duplicate Sysbox entries in /etc/subuid

The host's `/etc/subuid` and `/etc/subgid` files contain the host user-id and
group-id ranges that Sysbox assigns to the containers. These files should
have a single entry for user `sysbox` that looks similar to this:

```
$ more /etc/subuid
sysbox:165536:65536
```

If for some reason this file has more than one entry for user `sysbox`, you'll
see the following error when creating a container:

```
docker: Error response from daemon: OCI runtime create failed: error in the container spec: invalid user/group ID config: sysbox-runc requires user namespace uid mapping array have one element; found [{0 231072 65536} {65536 296608 65536}]: unknown.
```

## Bind Mount Permissions Error

When running a system container with a bind mount, you may see that
the files and directories associated with the mount have
`nobody:nogroup` ownership when listed from within the container.

This typically occurs when the source of the bind mount is owned by a
user on the host that is different from the user on the host to which
the system container's root user maps. Recall that Sysbox containers
always use the Linux user namespace and thus map the root user in the
system container to a non-root user on the host.

Refer to [System Container Bind Mount Requirements](storage.md#system-container-bind-mount-requirements) for
info on how to set the correct permissions on the bind mount.

## Failed to Setup Docker Volume Manager Error

When creating a system container, Docker may report the following error:

```console
docker run --runtime=sysbox-runc -it ubuntu:latest
docker: Error response from daemon: OCI runtime create failed: failed to setup docker volume manager: host dir for docker store /var/lib/sysbox/docker can't be on ..."
```

This means that Sysbox's `/var/lib/sysbox` directory is on a
filesystem not supported by Sysbox.

This directory must be on one of the following filesystems:

-   ext4
-   btrfs

The same requirement applies to the `/var/lib/docker` directory.

This is normally the case for vanilla Ubuntu installations, so this
error is not common.

## Failed to register with sysbox-mgr or sysbox-fs

While creating a system container, Docker may report the following error:

```console
$ docker run --runtime=sysbox-runc -it alpine
docker: Error response from daemon: OCI runtime create failed: failed to register with sysbox-mgr: failed to invoke Register via grpc: rpc error: code = Unavailable desc = all SubConns are in TransientFailure, latest connection error: connection error: desc = "transport: Error while dialing dial unix /run/sysbox/sysmgr.sock: connect: connection refused": unknown.
```

or

```console
docker run --runtime=sysbox-runc -it alpine
docker: Error response from daemon: OCI runtime create failed: failed to pre-register with sysbox-fs: failed to register container with sysbox-fs: rpc error: code = Unavailable desc = all SubConns are in TransientFailure, latest connection error: connection error: desc = "transport: Error while dialing dial unix /run/sysbox/sysfs.sock: connect: connection refused": unknown.
```

This likely means that the sysbox-mgr and/or sysbox-fs daemons are not running (for some reason).

Check that these are running via systemd:

    $ systemctl status sysbox-mgr
    $ systemctl status sysbox-fs

If either of these services are not running, use Systemd to restart them:

```console
$ sudo systemctl restart sysbox
```

Normally Systemd ensures these services are running and restarts them automatically if
for some reason they stop.

## Failed to interact with sysbox-fs or sysbox-mgr

The following error may be reported within a system container or any of its
inner (child) containers:

```
# ls /proc/sys
ls: cannot access '/proc/sys': Transport endpoint is not connected
```

This error usually indicates that sysbox-fs daemon (and potentially sysbox-mgr
too) has been restarted after the affected system container was initiated. In
this scenario user is expected to recreate (stop and start) all the
active Sysbox containers.

## Docker reports failure setting up ptmx

When creating a system container with Docker + Sysbox, if Docker reports an error such as:

```console
docker: Error response from daemon: OCI runtime create failed: container_linux.go:364: starting container process caused "process_linux.go:533: container init caused \"rootfs_linux.go:67: setting up ptmx caused \\\"remove dev/ptmx: device or resource busy\\\"\"": unknown.
```

It likely means the system container was launched with the Docker `--privileged`
flag (and this flag is not compatible with Sysbox as described
[here](limitations.md)).

## Docker exec fails

You may hit this problem when doing an `docker exec -it my-syscont bash`:

    OCI runtime exec failed: exec failed: container_linux.go:364: starting container process caused "process_linux.go:94: executing setns process caused \"exit status 2\"": unknown

This occurs if the `/proc` mount inside the system container is set to "read-only".

For example, if you launched the system container and run the following command in it:

    $ mount -o remount,ro /proc

## Sysbox Logs

### sysbox-mgr and sysbox-fs

The Sysbox daemons (i.e. sysbox-fs and sysbox-mgr) will log information related
to their activities in `/var/log/sysbox-fs.log` and `/var/log/sysbox-mgr.log`
respectively. These logs should be useful during troubleshooting exercises.

You can modify the log file location, log level, and log format. See [here](configuration.md#reconfiguration-procedure)
and [here](configuration.md#sysbox-log-configuration) for more info.

### sysbox-runc

For sysbox-runc, logging is handled as follows:

-   When running Docker + sysbox-runc, the sysbox-runc logs are actually stored in
    a containerd directory such as:

    `/run/containerd/io.containerd.runtime.v1.linux/moby/<container-id>/log.json`

    where `<container-id>` is the container ID returned by Docker.

-   When running sysbox-runc directly, sysbox-runc will not produce any logs by default.
    Use the `sysbox-runc --log` option to change this.

## The `/var/lib/sysbox` is not empty even though there are no containers

Sysbox stores some container state under the `/var/lib/sysbox` directory
(which for security reasons is only accessible to the host's root user).

When no system containers are running, this directory should be clean and
look like this:

```console
# tree /var/lib/sysbox
/var/lib/sysbox
├── containerd
├── docker
│   ├── baseVol
│   ├── cowVol
│   └── imgVol
└── kubelet
```

When a system container is running, this directory holds state for the container:

```console
# tree -L 2 /var/lib/sysbox
/var/lib/sysbox
├── containerd
│   └── f29711b54e16ecc1a03cfabb16703565af56382c8f005f78e40d6e8b28b5d7d3
├── docker
│   ├── baseVol
│   │   └── f29711b54e16ecc1a03cfabb16703565af56382c8f005f78e40d6e8b28b5d7d3
│   ├── cowVol
│   └── imgVol
└── kubelet
    └── f29711b54e16ecc1a03cfabb16703565af56382c8f005f78e40d6e8b28b5d7d3
```

If the system container is stopped and removed, the directory goes back to it's clean state:

```console
# tree /var/lib/sysbox
/var/lib/sysbox
├── containerd
├── docker
│   ├── baseVol
│   ├── cowVol
│   └── imgVol
└── kubelet
```

If you have no system containers created yet `/var/lib/sysbox` is not clean, it means
Sysbox is in a bad state. This is very uncommon as Sysbox is well tested.

To overcome this, you'll need to follow this procedure:

1) Stop and remove all system containers (e.g., all Docker containers created with the sysbox-runc runtime).

-   There is a bash script to do this [here](../../scr/rm_all_syscont).

2) Restart Sysbox:

```console
$ sudo systemctl restart sysbox
```

3) Verify that `/var/lib/sysbox` is back to a clean state:

```console
# tree /var/lib/sysbox
/var/lib/sysbox
├── containerd
├── docker
│   ├── baseVol
│   ├── cowVol
│   └── imgVol
└── kubelet
```

## Kubernetes-in-Docker fails to create pods

When running [K8s-in-Docker](kind.md), if you see pods failing to deploy, we suggest starting
by inspecting the kubelet log inside the K8s node where the failure occurs.

    $ docker exec -it <k8s-node> bash

    # journalctl -u kubelet

This log often has useful information on why the failure occurred.

One common reason for failure is that the host is lacking sufficient storage. In
this case you'll see messages like these ones in the kubelet log:

    Disk usage on image filesystem is at 85% which is over the high threshold (85%). Trying to free 1284963532 bytes down to the low threshold (80%).
    eviction_manager.go:168] Failed to admit pod kube-flannel-ds-amd64-6wkdk_kube-system(e3f4c428-ab15-48af-92eb-f07ce06aa4af) - node has conditions: [DiskPressure]

To overcome this, make some more storage room in your host and redeploy the
pods.


## Core-Dump generation

If problem cannot be explained by any of the previous bullets, then it may be
helpful to obtain core-dumps for both of the Sysbox daemons (i.e. `sysbox-fs` and
`sysbox-mgr`). As an example, find below the instructions to generate a core-dump
for `sysbox-fs` process.

- Enable core-dump creation by making use of the `ulimit` command:

    ```console
    $ ulimit -c unlimited
    ```

- We make use of the `gcore` tool to create core-dumps, which is usually included
as part of the `gdb` package in most of the Linux distros. Install `gdb` if not
already present in the system:

    For Debian / Ubuntu distros:

    ```console
    $ sudo apt-get install gdb
    ```

    For Fedora / CentOS / Redhat / rpm-based distros:

    ```console
    $ sudo yum install gdb
    ```

- Create core-dump file. Notice that Sysbox containers will continue to operate as
usual during (and after) the execution of this instruction, so no service impact
is expected.

    ```console
    $ sudo gcore `pidof sysbox-fs`
    ...
    Saved corefile core.195835
    ...
    ```

- Compress created core file:

    ```console
    $ sudo tar -zcvf core.195835.tar.gz core.195835

    $ ls -lrth core.195835.tar.gz
    -rw-r--r-- 1 root root 8.4M Apr 20 15:36 core.195835.tar.gz
    ```

- Create a Sysbox [issue](https://github.com/nestybox/sysbox/issues) and provide
a link to the generated core-dump.
