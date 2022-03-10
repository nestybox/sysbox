# Sysbox User Guide: Mounting and Sharing Host Storage

This document provides info on mounting storage into Sysbox containers.

## Contents

-   [Mounting Storage with Docker + Sysbox](#mounting-storage-with-docker--sysbox)
-   [Mounting Storage with Kubernetes + Sysbox](#mounting-storage-with-kubernetes--sysbox)
-   [Sharing Storage Between Sysbox Containers](#sharing-storage-between-sysbox-containers)
-   [Security Precautions for Storage Mounts](#security-precautions-for-storage-mounts)

## Mounting Storage with Docker + Sysbox

Sysbox containers support all Docker storage mount types:
[volume, bind, or tmpfs](https://docs.docker.com/storage/).

For bind mounts in particular, Sysbox leverages the Linux [ID-mapped mounts](design.md#id-mapped-mounts--v050-)
feature (kernel >= 5.12) or alternatively the [shiftfs](design.md#ubuntu-shiftfs-module)
kernel module (available on Ubuntu, Debian, and Flatcar) to ensure that the host
files that are bind-mounted into the container show up with proper user-ID and
group-ID inside the container. See the [design chapter](design.md) for more info
on this.

For example, if we have a host directory called `my-host-dir` where files
are owned by users in the range \[0:65536], and that directory is bind mounted
into a system container as follows:

```console
$ docker run --runtime=sysbox-runc -it --mount type=bind,source=my-host-dir,target=/mnt/my-host-dir alpine
```

then Sysbox will setup and ID-mapped mount on `my-host-dir` (or alternatively
mount shiftfs on it), causing the files to show up with the same ownership
(\[0:65536]) inside the container, even though the container's user-IDs and
group-IDs are mapped to a completely different set of IDs on the host (e.g.,
100000->165536).

This way, users need not worry about what host IDs are mapped into the container
via the Linux user-namespace. Sysbox takes care of setting things up so that the
bind mounted files show up with proper permissions inside the container.

This makes it possible for Sysbox containers to share files with the host or
with other containers, even if these have independent user-namespace ID mappings
(as assigned by Sysbox-EE for extra isolation).

Note that if neither ID-mapped mounts or shiftfs are present in your host, then
host files mounted into the Sysbox container will show up as owned by
`nobody:nogroup` inside the container.

## Mounting Storage with Kubernetes + Sysbox

Kubernetes supports several [volume types](https://kubernetes.io/docs/concepts/storage/volumes) for
mounting into pods.

Pods launched with Kubernetes + Sysbox (aka Sysbox pods) support several of
these volume types, though we've not yet verified all.

The following volume types are known to work with Sysbox:

-   ConfigMap
-   EmptyDir
-   gcePersistentDisk
-   hostPath
-   local
-   secret
-   subPath

Other volume types may also work, though Nestybox has not tested them. Note that
Sysbox must mount the volumes with ID-mapping in order for them to show up with
proper permissions inside the Sysbox container, using either the ID-mapped
mounts or shiftfs mechanisms (see the prior section). This may create
incompatibilities with some Kubernetes volume types (other than those listed
above). If you find such an incompatibility, please file an issue in the
[Sysbox repo](https://github.com/nestybox/sysbox).

### Example: Mounting Host Volumes to a Sysbox Pod

The following spec creates a Sysbox pod with ubuntu-bionic + systemd +
Docker and mounts host directory `/root/somedir` into the pod's `/mnt/host-dir`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ubu-bio-systemd-docker
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
spec:
  runtimeClassName: sysbox-runc
  containers:
  - name: ubu-bio-systemd-docker
    image: registry.nestybox.com/nestybox/ubuntu-bionic-systemd-docker
    command: ["/sbin/init"]
    volumeMounts:
      - mountPath: /mnt/host-dir
        name: host-vol
  restartPolicy: Never
  volumes:
  - name: host-vol
    hostPath:
      path: /root/somedir
      type: Directory
```

When this pod is deployed, Sysbox will automatically setup ID shifting on the
pod's `/mnt/host-dir` (either with ID-mapped mounts or with shiftfs). As a
result that directory will show up with proper user-ID and group-ID ownership
inside the pod.

## Sharing Storage Between Sysbox Containers

To share storage between Sysbox containers, simply mount the storage to the
containers.

Even though each Sysbox container may use different user-namespace ID mappings,
Sysbox will leverage the ID-mapped mounts or shiftfs mechanisms to ensure the
containers see the storage with a consistent set of filesystem user-ID and
group-IDs.

## Security Precautions for Storage Mounts

When mounting storage into a container, note the following:

**Any files or directories mounted into the container are writable from
within the container (unless the mount is "read-only"). Furthermore, when the
container's root user writes to these mounted files or directories, it will do
so as if it were the root user on the host.**

In other words, be aware that files or directories mounted into the container
are **not isolated** from the container. Thus, make sure to only mount host
files / directories into the container when it's safe to do so.
