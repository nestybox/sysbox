# Sysbox User Guide: Configuration

This document describes Sysbox configuration.

Note that usually you don't need to modify Sysbox's default configuration.

## Contents

-   [Reconfiguration Procedure](#reconfiguration-procedure)
-   [Sysbox Configuration Options](#sysbox-configuration-options)
-   [Sysbox Kernel Parameter Configurations](#sysbox-kernel-parameter-configurations)

## Reconfiguration Procedure

The Sysbox installer starts the [Sysbox components](design.md#sysbox-components)
automatically as a Systemd service.

Normally this is sufficient and the user need not worry about reconfiguring
Sysbox.

However, there are scenarios where the daemons may need to be
reconfigured (e.g., to enable a given option on sysbox-fs or
sysbox-mgr).

For example, when troubleshooting, it's useful to increase the log level by
passing the `--log-level debug` to the sysbox-fs or sysbox-mgr daemons.

In order to reconfigure Sysbox, do the following:

1) Stop all system containers (there is a sample script for this [here](../../scr/rm_all_syscont)).

2) Modify the desired Systemd service initialization command.

   For example, if you wish to change the log-level, do the following:

```console
$ sudo sed -i --follow-symlinks '/^ExecStart/ s/$/ --log-level debug/' /lib/systemd/system/sysbox-fs.service
$
$ egrep "ExecStart" /lib/systemd/system/sysbox-fs.service
ExecStart=/usr/local/sbin/sysbox-fs --log /var/log/sysbox-fs.log --log-level debug
```

3) Reload Systemd to digest the previous change:

```console
$ sudo systemctl daemon-reload
```

4) Restart the sysbox service:

```console
$ sudo systemctl restart sysbox
```

5) Verify the sysbox service is running:

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

That's it. You can now launch system containers.

Note that even though Sysbox is comprised of various daemons and its
respective services, you should only interact with its outer-most
systemd service called "sysbox".

## Sysbox Configuration Options

As root, type `sysbox-mgr --help` to get a list of command line options
supported by the sysbox-mgr component.

Same for sysbox-fs: `sysbox-fs --help`.

## Sysbox Data Store Configuration

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
systemd service:

```
ExecStart=/usr/local/sbin/sysbox-mgr --data-root /some/other/dir
```

Once reconfigured, restart the Sysbox systemd service as described in
[Reconfiguration Procedure](#reconfiguration-procedure) above.

Finally: if you create a system container and mount a Docker
volume (or a host directory) into the container's `/var/lib/docker`
directory, then the inner Docker images are stored in that Docker
volume rather than in the Sysbox data store. This also means
that the data can persist across the container's life-cycle
(i.e., it won't be deleted when the container is removed). See [this section in the quickstart guide](../quickstart/dind.md##persistence-of-inner-container-images-using-docker-volumes)
for an example of how to do this.

## Sysbox Kernel Parameter Configurations

Sysbox requires some kernel parameters to be modified from their default values,
in order to ensure the kernel allocates sufficient resources needed to run
system containers.

The Sysbox installer performs these changes automatically.

Below is the list of kernel parameters configured by Sysbox (via `sysctl`):

```
fs.inotify.max_queued_events = 1048576
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1048576
kernel.keys.maxkeys = 20000
kernel.keys.maxbytes = 4000000
```
