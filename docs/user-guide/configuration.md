# Sysbox User Guide: Configuration

This document describes Sysbox configuration.

Note that usually you don't need to modify Sysbox's default configuration.

## Contents

-   [Sysbox Systemd Services](#sysbox-systemd-services)
-   [Reconfiguration Procedure](#reconfiguration-procedure)
-   [Sysbox Configuration Options](#sysbox-configuration-options)
-   [Sysbox Log Configuration](#sysbox-log-configuration)
-   [Sysbox Data Store Configuration \[ v0.3.0+ \]](#sysbox-data-store-configuration--v030-)
-   [Container Capabilities Configuration \[ v0.5.0+ \]](#container-capabilities-configuration--v050-)
-   [Speeding up Sysbox by Disallowing Trusted Overlay Xattributes](#speeding-up-sysbox-by-disallowing-trusted-overlay-xattributes)
-   [Ignoring Chowns of Sysfs](#ignoring-chowns-of-sysfs)
-   [Disabling ID-mapped Mounts on Sysbox](#disabling-id-mapped-mounts-on-sysbox)
-   [Disabling Shiftfs on Sysbox](#disabling-shiftfs-on-sysbox)
-   [Sysbox Kernel Parameter Configurations](#sysbox-kernel-parameter-configurations)

## Sysbox Systemd Services

The Sysbox installer starts the [Sysbox components](design.md#sysbox-components)
automatically as Systemd services.

Sysbox is made up of 3 systemd services:

-   `sysbox.service`: top level service to start, stop, and restart Sysbox.
-   `sysbox-mgr.service`: sub-service that starts the sysbox-mgr daemon
-   `sysbox-fs.service`: sub-service that starts the sysbox-fs daemon

These are usually located in `/lib/systemd/system/`.

Users normally interact with the top-level `sysbox.service` to start, stop, and
restart Sysbox.

For example, to stop Sysbox you can type:

```console
$ sudo systemctl stop sysbox
```

**NOTE: Make sure all Sysbox containers are stopped and removed before stopping
Sysbox, as otherwise they will stop operating properly.**

To start Sysbox again you can type:

```console
$ sudo systemctl start sysbox
```

Users don't normally interact with the sub-services (sysbox-mgr and sysbox-fs),
except when you wish to modify command line parameters associated with these
(see next section).

## Reconfiguration Procedure

Normally users need not worry about reconfiguring Sysbox as the default
configuration suffices in most cases. However, there are scenarios where the
sysbox-mgr or sysbox-fs daemons may need to be reconfigured.

You can type `sudo sysbox-fs --help` or `sudo sysbox-mgr --help` to see the
command line configuration options that each take.

For example, when troubleshooting, it's useful to increase the log level by
passing the `--log-level debug` to the sysbox-fs or sysbox-mgr daemons.

The reconfiguration is done by modifying the systemd sub-service associated
with sysbox-fs and/or sysbox-mgr (per your needs). Once the systemd sub-service
is reconfigured, you restart Sysbox using the [top level Sysbox service](#sysbox-systemd-services).

**NOTE: Always use the top level Sysbox service to start, stop, and restart
Sysbox. Do not do this on the sub-services directly.**

For example, to reconfigure Sysbox, do the following:

1.  Stop all system containers (there is a sample script for this [here](../../scr/rm_all_syscont)).

2.  Modify the `ExecStart` command in the appropriate systemd service
    (`sysbox-fs.service` or `sysbox-mgr.service`):

    For example, if you wish to change the log-level of the sysbox-fs service,
    do the following:

```console
$ sudo sed -i --follow-symlinks '/^ExecStart/ s/$/ --log-level debug/' /lib/systemd/system/sysbox-fs.service
$
$ egrep "ExecStart" /lib/systemd/system/sysbox-fs.service
ExecStart=/usr/bin/sysbox-fs --log /var/log/sysbox-fs.log --log-level debug
```

3.  Reload Systemd to digest the previous change:

```console
$ sudo systemctl daemon-reload
```

4.  Restart the sysbox (top-level) service:

```console
$ sudo systemctl restart sysbox
```

5.  Verify the sysbox service is running:

```console
$ sudo systemctl status sysbox.service
● sysbox.service - Sysbox General Service
   Loaded: loaded (/lib/systemd/system/sysbox.service; enabled; vendor preset: enabled)
   Active: active (exited) since Sun 2019-10-27 05:18:59 UTC; 14s ago
  Process: 26065 ExecStart=/bin/true (code=exited, status=0/SUCCESS)
 Main PID: 26065 (code=exited, status=0/SUCCESS)

Oct 27 05:18:59 disco1 systemd[1]: sysbox.service: Succeeded.
Oct 27 05:18:59 disco1 systemd[1]: Stopped Sysbox General Service.
Oct 27 05:18:59 disco1 systemd[1]: Stopping Sysbox General Service...
Oct 27 05:18:59 disco1 systemd[1]: Starting Sysbox General Service...
Oct 27 05:18:59 disco1 systemd[1]: Started Sysbox General Service.
```

That's it. You can now start using Sysbox with the updated configuration.

## Sysbox Configuration Options

As root, type `sysbox-mgr --help` to get a list of command line options
supported by the sysbox-mgr component.

Same for sysbox-fs: `sysbox-fs --help`.

## Sysbox Log Configuration

The Sysbox logs are located at `/var/log/sysbox-*.log`. You can change the
location of the log file via the `--log` option in both the sysbox-fs and
sysbox-mgr daemons.

In addition, the format of the logs can be controlled. By default they are in
text format, but you can change them to json format via the `--log-format`
config option in both the sysbox-mgr and sysbox-fs daemons.

Finally, the log-level (info, debug, etc) can be changed via the
`--log-level` option. This is useful for debugging.

## Sysbox Data Store Configuration \[ v0.3.0+ ]

As part of its operation, Sysbox uses a host directory as a data
store. By default, Sysbox uses `/var/lib/sysbox`, but this can be
changed if needed (see below).

Depending on the workloads running on the system containers created by Sysbox,
the amount of data stored in the Sysbox data store can be significant (hundreds
of MBs to several GBs).

We recommend that the Sysbox data store be no smaller than 10GB, but
the capacity really depends on how many system container instances you
will be running, whether inside of those containers you will be
deploying inner containers, and the size of those inner container
images.

For example, when running Docker inside a system container, the inner
Docker images are stored in this Sysbox's data store. The size of
those can add up quickly. Similarly, when running Kubernetes inside a
system container, the Kubelet's data is also stored in the Sysbox's
data store.

It's important to understand that this data resides in the Sysbox data
store only while the container is running. When the container stops,
Sysbox deletes the associated data (containers are stateless by
default).

You can change the location of the Sysbox data store by passing the
`--data-root` option to the Sysbox Manager daemon via its associated
systemd service (`/lib/systemd/system/sysbox-mgr.service`):

    ExecStart=/usr/bin/sysbox-mgr --data-root /some/other/dir

Once reconfigured, restart the Sysbox systemd service as described in
[Reconfiguration Procedure](#reconfiguration-procedure) above.

Finally: if you create a system container and mount a Docker volume (or a host
directory) into the container's `/var/lib/docker` directory, then the inner
Docker images are stored in that Docker volume rather than in the Sysbox data
store. This also means that the data can persist across the container's
life-cycle (i.e., it won't be deleted when the container is removed).
See [this section in the quickstart guide](../quickstart/dind.md#persistence-of-inner-container-images-using-docker-volumes)
for an example of how to do this.

## Container Capabilities Configuration \[ v0.5.0+ ]

By default, Sysbox assigns process capabilities in the container as
follows:

* Enables all process capabilities for the system container's init process when
  owned by the root user.

* Disables all process capabilities for the system container's init process when
  owned by a non-root user.

This mimics the way capabilities are assigned to processes on a physical host (or
a VM) and relieves users of the burden on having to understand what capabilities
are needed by the processes running inside the container.

Note that with Sysbox, container capabilities are always isolated from the host
via the Linux user-namespace, which Sysbox enables on all containers. This means
you can run a root process with full capabilities inside the container in a more
secure way than with regular containers. See the [security chapter](security.md#process-capabilities)
for more on this.

While Sysbox's default behavior for assigning capabilities is beneficial in most
cases, it has the drawback that it does not allow fine-grained control of the
capabilities used by the Sysbox container init process (e.g., Docker's
`--cap-add` and `--cap-drop` don't have any effect). In some situations, having
such control is beneficial.

To overcome this, starting with Sysbox v0.5.0 it's possible to configure
Sysbox to honor the capabilities passed to it by the higher level
container manager (e.g., Docker or Kubernetes) via the container's OCI spec.

The configuration can be done on a per-container basis, or globally for
all containers.

To do this on a per-container basis, pass the `SYSBOX_HONOR_CAPS=TRUE`
environment variable to the container, as follows:

```
$ docker run --runtime=sysbox-runc -e SYSBOX_HONOR_CAPS=TRUE --rm -it alpine
/ # cat /proc/self/status | grep -i cap
CapInh: 00000000a80425fb
CapPrm: 00000000a80425fb
CapEff: 00000000a80425fb
CapBnd: 00000000a80425fb
CapAmb: 0000000000000000
```

To do this globally (i.e., for all Sysbox containers), configure the sysbox-mgr
with the `--honor-caps` command line option (see [above](#reconfiguration-procedure).
If you set `--honor-caps` globally, you can always deploy a container with the
default behavior by passing environment variable `SYSBOX_HONOR_CAPS=FALSE`.

Note that while configuring Sysbox to honor capabilities gives you full control
over the container's process capabilities (which is good for extra security),
the drawback is that you must understand all the capabilities required by the
processes inside the container (e.g., if you run Docker inside the Sysbox
container, you must understand what capabilities Docker requires in order to
operate properly; same if you run systemd inside the container). This can be
tricky since such software is complex and may require different capabilities
depending on what functions it's performing inside the container.

## Speeding up Sysbox by Disallowing Trusted Overlay Xattributes

The [overlayfs](https://docs.kernel.org/filesystems/overlayfs.html) filesystem
is commonly used by container managers (e.g., Docker or Kubernetes) to set up
the container's root filesystem. To support file removal, overlayfs uses a
concept called [whiteouts](https://docs.kernel.org/filesystems/overlayfs.html#whiteouts-and-opaque-directories)
which relies on setting the `trusted.overlay.opaque` extended attribute (xattr) on the removed file.

Setting `trusted.*` xattrs requires a process to have elevated privileges (i.e,
`CAP_SYS_ADMIN`) since they are expected to be set by admin processes, not by
ordinary ones. In addition, Linux does not allow `trusted.*` xattrs to be set
from within a user-namespace (even if a process has `CAP_SYS_ADMIN` within the
user-namespace), given that otherwise a regular user could create a
user-namespace and set the `trusted.*` xattr on the file.

This limitation for setting `trusted.*` xattr from within a user-namespace
creates a problem for containers that are secured with the user-namespace, such
as Sysbox containers. The reason is that it prevents software such as Docker,
which commonly uses overlayfs and sets the `trusted.overlay.opaque` xattr on
files, from working properly inside the Sysbox container.

To overcome this, Sysbox has a mechanism that allows the
`trusted.overlay.opaque` xattr to be set from within a container. It does this
by trapping the `*xattr()` syscalls inside the container (e.g., `setxattr`,
`getxattr`, etc.) and performing the required operation at host level. This is
pretty safe, given that the container processes can only set the
`trusted.overlay.opaque` xattr on files within the container's chroot jail.

The drawback however is that this can impact performance (sometimes severely),
particularly in workloads that perform lots of `*xattr()` syscalls from within
the container.

Fortunately, starting with Linux kernel 5.11, overlayfs supports whiteouts
using an alternative `user.overlay.opaque` xattr which can be configured
from within a user-namespace (see [here](https://docs.kernel.org/filesystems/overlayfs.html#user-xattr))
In addition, Docker versions >= 20.10.9 include code that takes advantage
of this feature.

Therefore, if your host has kernel >= 5.11 and you run Docker >= 20.10.9 inside
a Sysbox container, you don't need Sysbox to trap the `*xattr()` syscalls, which
in turn improves performance (in some cases significantly).

It's possible to configure Sysbox to not trap the `*xattr()` syscalls. This
can be done on a per-container basis by passing the `SYSBOX_ALLOW_TRUSTED_XATTR=FALSE`
environment variable to the container:

```
$ docker run --runtime=sysbox-runc -e SYSBOX_ALLOW_TRUSTED_XATTR=FALSE --rm -it alpine
```

In essence, this tells Sysbox to not allow the container to set `trusted.overlay.opaque`
inside the container, which in turn means it won't trap the `*xattr()` syscalls.

You can also configure this globally (i.e., for all Sysbox containers), by
starting the sysbox-mgr with the `--allow-trusted-xattr=false` command line
option (see [above](#reconfiguration-procedure). If you set
`--allow-trusted-xattr=false` globally, you can always deploy a Sysbox container
with the default behavior by passing environment variable
`SYSBOX_ALLOW_TRUSTED_XATTR=TRUE`.

## Ignoring Chowns of Sysfs

Inside a Sysbox container, the `/sys` directory (i.e., the sysfs mountpoint)
shows up as owned by `nobody:nogroup` (rather than `root:root`). Moreover,
changing the ownership of `/sys/` to `root:root` fails with `Operation not
permitted`. This is due to a technical limitation in Sysbox and the Linux
kernel.

```
$ docker run --runtime=sysbox-runc -it --rm alpine

/ # ls -l / | grep sys
dr-xr-xr-x   13 nobody   nobody           0 Mar 11 23:14 sys

/ # chown root:root  /sys
chown: /sys: Operation not permitted
```

Though not common, some application that users run inside Sysbox containers
(notably the `rpm` package manager) may try to change the ownership of `/sys`
inside the container. Since this operation fails, the application reports an
error and exits.

To overcome this, Sysbox can be configured to ignore chowns to `/sys` inside
the container by passing the `SYSBOX_IGNORE_SYSFS_CHOWN=TRUE` environment variable
to the container, as shown below:

```
$ docker run --runtime=sysbox-runc -e SYSBOX_IGNORE_SYSFS_CHOWN=TRUE --rm -it alpine

/ # chown root:root /sys
/ # echo $?
0

/ # ls -l / | grep sys
dr-xr-xr-x   13 nobody   nobody           0 Mar 11 23:17 sys
```

You can also configure this globally (i.e., for all Sysbox containers), by
starting the sysbox-mgr with the `--ignore-sysfs-chown` command line
option (see [above](#reconfiguration-procedure).

Note that configuring Sysbox to ignore chown on sysfs requires that Sysbox
trap the `chown` syscall. This can slow down the container, in some
cases significantly (i.e., if the processes inside the container perform
lots of chown syscalls).

## Disabling ID-mapped Mounts on Sysbox

As mentioned in the [design chapter](design.md#id-mapped-mounts--v050-), Sysbox
uses a Linux kernel feature called ID-mapped mounts (available in kernel >= 5.12)
to expose host files inside the (rootless) container with proper permissions.

While not usually required (except for testing or debugging), it's possible to
disable Sysbox's usage of ID-mapped mounts by passing the
`--disable-idmapped-mount` option to the sysbox-mgr's command line. See the
section on [reconfiguration procedure](#reconfiguration-procedure) above for
further info on how to do this.

## Disabling Shiftfs on Sysbox

Shiftfs serves a purpose similar to ID-mapped mounts, as described in the
[design chapter](design.md#shiftfs-module).

While not usually required (except for testing or debugging), it's possible to
disable Sysbox's usage of shiftfs by passing the
`--disable-shiftfs` option to the sysbox-mgr's command line. See the
section on [reconfiguration procedure](#reconfiguration-procedure) above for
further info on how to do this.

## Sysbox Kernel Parameter Configurations

Sysbox requires some kernel parameters to be modified from their default values,
in order to ensure the kernel allocates sufficient resources needed to run
system containers.

The Sysbox installer performs these changes automatically.

Below is the list of kernel parameters configured by Sysbox (via `sysctl`):

```console
fs.inotify.max_queued_events = 1048576
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1048576
kernel.keys.maxkeys = 20000
kernel.keys.maxbytes = 400000
```
