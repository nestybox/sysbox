# Sysbox Quick Start Guide: Storage

## Sharing Storage Among System Containers

It's easy to share storage among multiple system containers by simply
bind-mounting the shared storage into each system container.

1) Create the shared storage on the host. In this example we use
   a Docker volume.

```console
$ docker volume create shared-storage
shared-storage
```

2) Create a system container and mount the shared storage volume into it:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname syscont --mount source=shared-storage,target=/mnt/shared-storage alpine:latest
/ #
```

3) From the system container, add a shared file to the shared storage:

```console
/ # touch /mnt/shared-storage/shared-file
/ # ls -l /mnt/shared-storage/shared-file
-rw-r--r--    1 root     root             0 Oct 24 22:08 /mnt/shared-storage/shared-file
```

4) In another shell, create another system container and mount the shared storage volume into it:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname syscont2 --mount source=shared-storage,target=/mnt/shared-storage alpine:latest
/ #
```

5) Confirm that the second system container sees the shared file:

```console
/ # ls -l /mnt/shared-storage/shared-file
-rw-r--r--    1 root     root             0 Oct 24 22:08 /mnt/shared-storage/shared-file
```

Notice that both system containers see the shared file with `root:root`
permissions, even though each system container is using the Linux user namespace
with user-ID and group-ID mappings.

The reason both system containers see the correct `root:root` ownership on the
shared storage is through the magic of the Ubuntu shiftfs filesystem, which
Sysbox mounts over the shared storage.

From the first system container:

```console
/ # mount | grep shared-storage
/var/lib/docker/volumes/shared-storage/_data on /mnt/shared-storage type shiftfs (rw,relatime)
```

In the example above we used a Docker volume as the shared storage. However, we
can also use an arbitrary host directory as the shared storage. We need to
simply bind-mount it to the system containers.
