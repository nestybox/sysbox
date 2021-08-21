# Sysbox User Guide: Configuration

This document describes Sysbox configuration.

Note that usually you don't need to modify Sysbox's default configuration.

## Contents

-   [Sysbox Systemd Services](#sysbox-systemd-services)
-   [Reconfiguration Procedure](#reconfiguration-procedure)
-   [Sysbox Configuration Options](#sysbox-configuration-options)
-   [Sysbox Log Configuration](#sysbox-log-configuration)
-   [Sysbox Data Store Configuration \[ v0.3.0+ \]](#sysbox-data-store-configuration--v030-)
-   [Sysbox Kernel Parameter Configurations](#sysbox-kernel-parameter-configurations)

## Sysbox Systemd Services

The Sysbox installer starts the [Sysbox components](design.md#sysbox-components)
automatically as Systemd services.

Sysbox is made up of 3 systemd services:

-   `sysbox.service`: top level service to start, stop, and restart Sysbox.
-   `sysbox-mgr.service`: sub-service that starts the sysbox-mgr daemon
-   `sysbox-fs.service`: sub-service that starts the sysbox-fs daemon

These are norally located in `/lib/systemd/system/`.

Users normally interact with the top-level `sysbox.service` to start, stop, and
restart Sysbox.

For example, to stop Sysbox you can type:

```console
$ sudo systemctl stop sysbox
```

**NOTE: Make sure all Sysbox containers are stopped and removed before stopping
Sysbox, as otherwise the will stop operating properly.**

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

That's it. You can now start using Sysbox.

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
