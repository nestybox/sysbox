# Sysbox Internal User Guide: Inner Docker Image Sharing

## Background

-   In order to bypass the limitation that overlayfs can't be mounted on
    top of an overlayfs mount, Sysbox creates a directory on the host
    for each sys container and bind-mounts it on the container's docker
    data-root (i.e., `/var/lib/docker`). We call this host directory the
    sysbox "inner-docker-vol". There is one per sys container.

-   Since a sys container image may contain inner Docker images within
    it, when the sys container starts Sysbox copies the contents of the
    image's inner Docker data root (i.e., inner `/var/lib/docker`) to the
    corresponding docker-vol.  Conversely, when the sys container is
    paused or stops, we copy back from the docker-vol to the
    container's root directory (so that docker builds/commits can
    "bake-in" inner images).

## Problem

-   The copy operations described above cause performance and resource overhead:

    -   The container start and stop times are impacted.

    -   The sysbox docker-vol results in storage overhead.

-   This overhead occurs for each sys container.

-   The overhead is significant for sys container images that include
    large inner container images (e.g., k8s node images).

    -   start time = ~10 secs

    -   overhead = 1.7GB per sys container

## Solution

-   A solution is to add support in Sysbox for sharing the inner
    container docker images among sys containers.

-   That is, all sys containers that are based from the same sys
    container image will share the inner docker images and use
    copy-on-write (COW), such that the inner docker daemons can operate
    independently of each other.

-   The sharing of the inner docker images using COW is done by having
    sysbox use overlayfs itself, as described below.

-   The solution is such that the first sys container associated with a
    given image will pay the overhead described above, but all
    subsequent sys containers will not. This results in significant
    improvements as described above.

## Docker Volume Manager (dvm)

The solution described above is implemented by the "docker volume
manager" package, used by the sysbox-mgr.

### DVM Directories

The dvm creates the following host directories for it's operations.

#### Image Volume

-   For a given sys container **image**, this directory contains a copy
    of the inner docker images. That is, there is one of these per sys
    container image, not per sys container. And only if the sys
    container image has inner Docker images within it.

-   The structure of the dir is as follows:

```
    /var/lib/sysbox/docker
      imgVol/
        syscont-image0/
          inner-image0
          inner-image1
        syscont-image1/
          inner-image0
          inner-image1
```

#### Base Volume

-   For each sys container, the base volume contains a copy of the sys
    container's inner "/var/lib/docker" directory. If the sys container
    has inner docker images preloaded in it, the copy _excludes_ the
    preloaded inner docker images.

-   The base volume is bind-mounted into the sys container's
    "/var/lib/docker" dir.

-   The structure of the dir is as follows:

```
    /var/lib/sysbox/docker
      baseVol/
        syscont0
          var-lib-docker/
            <container's var/lib/docker, without overlay2 images>
```

#### Copy-On-Write (COW) Volume

-   For each sys container, the copy-on-write (cow) volume contains the
    "magic" that makes image sharing works among sys containers work.

-   The structure of the dir is as follows:

```
    /var/lib/sysbox/docker
      cowVol/
        syscont0/
            inner-image0/
              lower -> /soft/link/to/imgVol/syscont-image0/inner-image0/diff
              merged
              upper
              work
            inner-image1/
              lower -> /soft/link/to/imgVol/syscont-image0/inner-image1/diff
              merged
              upper
              work
            ...
        syscont1/
            inner-image0/
            ...
```

-   Basically, for each sys container inner docker image layer, the cow
    volume has an overlayfs mount. The overlayfs mount has as its
    "lower" dir a soft-link to the corresponding inner docker image
    layer in the image volume. The "merged" dir contains the merged
    overlayfs mount.

-   The "merged" dir for each inner image is bind-mounted into the sys
    container's "/var/lib/docker/overlay2/<inner-image>/diff" directory.
    In other words, inside the sys container, each preloaded inner image
    layer is backed by an overlayfs mount. This allows the inner images
    to be shared among all sys containers that use the same sys
    container image, yet be independently writable for each sys
    container using copy-on-write (implemented by overlayfs).

### First sys container start

-   The steps below apply to the first sys container associated with a
    given image.

-   The dvm determines if the sys container has inner images.

    -   If so, it creates subdirs in the image vol, cow vol, and base vol.

    -   Otherwise it simply creates subdirs in the base vol.

-   When creating the image vol:

    -   One of these for all sys containers based off the same image.

    -   Sysbox copies the sys container inner docker images directories to this new dir.

        -   Those in the sys container's `/var/lib/docker/overlay2/inner-image` dir, for each inner-image.

        -   This copy can be slow if the inner docker has many images.

        -   Skips the `/var/lib/docker/overlay2/l` dir (only has symlinks)

    -   Note: the inner docker images in this dir will be shared by all
        sibling sys containers using COW (with overlayfs).

-   When creating the cow vol:

    -   One of these per sys container.

    -   Sysbox creates the cow vol, and setups the overlayfs mounts for
        each of the sys container's inner docker images.

        -   For each inner docker image in the sys container:

    -   For example:

          image-id
            lower -> /path/to/inner-docker-image-store/syscont-image-id/inner-image-id
            merged
            upper
            work

        -   mounts overlayfs as follows:

            -   `mount -t overlay overlay -o lowerdir=lower,upperdir=upper,workdir=work merged`

    -   This allows the inner docker image layers to be shared among several
        sys containers using COW.

-   When creating the base vol:

    -   One of these per sys container.

    -   Sysbox copies the sys container's "/var/lib/docker" contents into the base vol.

        -   If the sys container has preloaded inner docker images, the copy
            skips the inner images diffs (i.e.,
            "/var/lib/docker/overlay2/inner-image/diff" directories).

-   Sysbox mounts the following into the sys container:

    -   Bind mounts the base vol to the sys container's `/var/lib/docker`

    -   If the sys container has preloaded inner images, bind mounts the
        "image-id/merged" dir in the cow volume to the sys container's
        `/var/lib/docker/overlay2/image-id/diff`.

-   After all of this, the sys container's `/var/lib/docker` will have
    the following characteristics:

    -   It's backed by ext4 (assuming that's the host filesystem).

        -   This allows the inner docker to create overlayfs mounts inside of it.

    -   It contains the contents of the sys container image's `/var/lib/docker`.

        -   Including inner images.

    -   Each inner image layer in the sys container's
        `/var/lib/docker/overlay2/inner-image/diff` subdir is backed by an
        overlayfs mount on the host (`cowVol/sys-container-id/image-id/merged`).

    -   The inner docker is allowed to use that layer as a overlayfs lower
        layer for it's inner containers. It can also delete the layer or
        modify it as needed. Any changes done to this layer from within
        the sys container are stored in the sysbox dvm cow volume
        (`cowVol/sys-container-id/image-id/upper` directory).

### Subsequent Container Starts

-   Same as for the first sys container, except that creation of the
    image volume is skipped (because all sys containers based from the
    same image share the same image volume).

-   This is where the storage overhead savings and container startup
    time gains are realized.

### Sys Container Pause / Stop

-   When a sys container is paused or stopped, Sysbox must copy-back the
    contents of the base volume and cow volumes associated with the sys
    container to the container's rootfs.

-   First, it copies the contents of the base volume to the rootfs
    `/var/lib/docker` dir.

    -   If inner image sharing is used, this is a quick copy since sys
        container preloaded inner docker images are not copied here.

-   Then, it copies the contents of the cow volume to the rootfs
    `/var/lib/docker/overlay2/image-id/diff` subdir as follows:

    -   Copies each `cowVol/sys-container-id/image-id/upper` subdir to the sys
        container's rootfs `/var/lib/docker/overlay2/image-id` directory:

    -   This is likely a quick copy since it's only copying overlayfs diffs.

### Sys Container Removal

-   Sysbox destroys the base vol and cow vol associated with the sys
    container.

### Last Sys Container Removal

-   When the last sys container associated with a given Docker image is
    removed, sysbox destroys the image volume subidr for that sys
    container's image.

-   NOTE: In the future we could apply a different heuristic to keep the
    image volume subdir for the sys container image around for a given
    time period so that future sys containers can re-use it. It's a
    performance vs. storage tradeoff.

### Uid/Gid Shifting

-   Sysbox needs to deal with uid(gid) ownership of the base vol and cow
    vol. The image vol is never exposed inside sys container's directly,
    so it always has "root:root" ownership on the host.

Sys cont start:

-   Sysbox modifies the uid(gid) of the base vol to match the sys
    container's root uid(gid):

-   Sysbox modifies the uid(gid) of the cow vols "merged" subdir
    to match the sys container's root uid(gid).

Sys cont stop:

-   Sysbox reverts the uid(gid) of the dirs/files when copying their
    contents back to the sys containers rootfs.

### Sys container image detection

-   In order to implement this solution, the docker vol manager be
    capable of determining when sys containers are based off the same
    container image.

-   It does this by querying Docker (via it's golang client API).

-   In the future, Sysbox should also query containerd.

    -   This will enables Sysbox to take advantage of the inner docker
        image sharing features for sys containers not launched with
        Docker.

### Feature switch

-   In sysbox-mgr, the above is done by default. It can be disabled via
    the sysbox-mgr's config option (`no-inner-docker-image-sharing`).

### Caveats of solution

-   Start of first sys container associated with a given image may be
    slow and copies all inner docker image data to dvm's image volume;
    subsequent sys container starts are fast and share image data.

### Corner cases

-   What if the container image does not have inner docker inside?

    -   Then inner docker image sharing is a no-op.

    -   The base vol for the sys container is allocated, mounted into the
        sys container's `/var/lib/docker`. It starts empty.

-   What if container image has inner `/var/lib/docker`, but it has no inner images

    -   Then inner docker image sharing is a no-op.

    -   The base vol for the sys container is allocated, its initial
        contents are copied from the sys container's `/var/lib/docker`,
        and it's bind-mounted into this same dir.

-   What if inner docker is not using the overlay2 driver?

    -   Same as above.

## Alternative Solutions

-   We won't implement these for now; listed for reference.

### Use btrfs to avoid overlayfs-on-overlayfs

-   Another solution is to configure the host docker to use the btrfs
    storage driver, instead of the default overlayfs storage driver.

-   With btrfs, we Sysbox does not need to use the sysbox docker-vol
    approach.

    -   Sysbox would need to be updated to detect that the outer docker is
        using btrfs.

-   It's a good solution but requires that users set up a btrfs partition
    and configure the host docker's data-root to point to it.

### overlayfs nesting

-   The ideal solution would be for overlayfs to support nesting. But
    this is out of our reach.

-   This would allows inner docker images to reside on top of outer
    docker's image layers, thereby avoiding the sysbox docker-vol
    described above.

    -   Solves both the slow startup and storage overhead problems.

-   With shiftfs, we need:

    -   overlayfs-on-shiftfs-on-overlayfs

-   Without shiftfs, we need:

    -   overlayfs-on-overlayfs

-   Neither of these currently work :(

## References

-   Sysbox issues for overlayfs

    <https://github.com/nestybox/sysbox/issues/46>
    <https://github.com/nestybox/sysbox/issues/93>
    <https://github.com/nestybox/sysbox/issues/180>
    <https://github.com/nestybox/sysbox/issues/336>
