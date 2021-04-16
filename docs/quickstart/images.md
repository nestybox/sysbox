# Sysbox Quick Start Guide: Preloading Inner Container Images into System Containers

This section shows how to preload inner container images into system container
images.

This way, you can deploy the system container image and run inner containers
without having to pull the inner container images from the network.

A complete list of advantages is described [here](../user-guide/images.md#preloading-inner-container-images-into-a-system-container--v012-).

There are two ways to do this:

-   Via `docker build`

-   Via `docker commit`

The following sections show examples of each.

## Building A System Container That Includes Inner Container Images \[ +v0.1.2 ]

**Check out this [video](https://asciinema.org/a/tYLbk5rQNOQtVgr236kErv7Gn?speed=2).**

Below are the steps:

1.  Reconfigure the host's Docker daemon to use `sysbox-runc` as it's default
    runtime by editing the `/etc/docker/daemon.json` file and restarting Docker:

```console
# more /etc/docker/daemon.json
{
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
        }
    },
    "default-runtime": "sysbox-runc"
}

$ systemctl restart docker.service
```

This is needed because during the build process, Docker is creating intermediate
containers for each Dockerfile instruction. Those intermediate containers must
be system containers deployed by Sysbox.

2.  Create a Dockerfile for the system container image. For example:

```dockerfile
FROM nestybox/alpine-docker

COPY docker-pull.sh /usr/bin
RUN chmod +x /usr/bin/docker-pull.sh && docker-pull.sh && rm /usr/bin/docker-pull.sh
```

This Dockerfile inherits from the `nestybox/alpine-docker` base image which simply contains
Alpine plus a Docker daemon (the Dockerfile is [here](https://github.com/nestybox/dockerfiles/blob/main/alpine-docker/Dockerfile)).

The presence of the inner Docker in the base image is required since we will use
it to pull the inner container images.

The key instruction in the Dockerfile shown above is the `RUN`
instruction. Notice that it's copying a script called `docker-pull.sh`
into the system container, executing it, and removing it.

The `docker-pull.sh` script is shown below.

```bash
#!/bin/sh

# dockerd start
dockerd > /var/log/dockerd.log 2>&1 &
sleep 2

# pull inner images
docker pull busybox:latest
docker pull alpine:latest

# dockerd cleanup (remove the .pid file as otherwise it prevents
# dockerd from launching correctly inside sys container)
kill $(cat /var/run/docker.pid)
kill $(cat /run/docker/containerd/containerd.pid)
rm -f /var/run/docker.pid
rm -f /run/docker/containerd/containerd.pid
```

The script starts the inner Docker, pulls the inner container images (in this
case the busybox and alpine images), and does some cleanup. Pretty simple.

The reason we need this script is because it's hard to put all of these commands
into a single Dockerfile `RUN` instruction. It's simpler to put them in a
separate script and call it from the `RUN` instruction.

3.  Do a `docker build` on this Dockerfile:

```console
$ docker build -t nestybox/syscont-with-inner-containers:latest .

Sending build context to Docker daemon  3.072kB
Step 1/3 : FROM nestybox/alpine-docker
 ---> b51716d05554
Step 2/3 : COPY docker-pull.sh /usr/bin
 ---> Using cache
 ---> df2af1f26937
Step 3/3 : RUN chmod +x /usr/bin/docker-pull.sh && docker-pull.sh && rm /usr/bin/docker-pull.sh
 ---> Running in 7fa2687f2385
latest: Pulling from library/busybox
7c9d20b9b6cd: Pulling fs layer
7c9d20b9b6cd: Verifying Checksum
7c9d20b9b6cd: Download complete
7c9d20b9b6cd: Pull complete
Digest: sha256:fe301db49df08c384001ed752dff6d52b4305a73a7f608f21528048e8a08b51e
Status: Downloaded newer image for busybox:latest
latest: Pulling from library/alpine
89d9c30c1d48: Pulling fs layer
89d9c30c1d48: Verifying Checksum
89d9c30c1d48: Download complete
89d9c30c1d48: Pull complete
Digest: sha256:c19173c5ada610a5989151111163d28a67368362762534d8a8121ce95cf2bd5a
Status: Downloaded newer image for alpine:latest
Removing intermediate container 7fa2687f2385
 ---> 9c33554fd4cf
Successfully built 9c33554fd4cf
Successfully tagged nestybox/syscont-with-inner-containers:latest
```

We can see from above that the Docker build process has pulled the
busybox and alpine container images and stored them inside the system
container image. Cool!

4.  Optionally revert the `default-runtime` config in step (1) (it's only needed
    for the Docker build).

5.  Optionally prune any dangling images created during the Docker build process
    to save storage.

```console
$ docker image prune
```

6.  Start a system container using the newly created image:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname=syscont nestybox/syscont-with-inner-containers:latest
/ #
```

7.  Start the inner Docker and verify the inner images are in there:

```console
/ # dockerd > /var/log/dockerd.log 2>&1 &

/ # docker image ls
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
alpine              latest              965ea09ff2eb        2 days ago          5.55MB
busybox             latest              19485c79a9bb        7 weeks ago         1.22MB
```

There they are!

You can preload as many inner container images as you want. Just keep in mind
that they will add to the size of the system container image.

### A Caveat on Inner Image Preloading

In the Dockerfile for the system container (see step (2) above), make sure that
the container's `/var/lib/docker` is not backed by a host volume. Otherwise, the
contents of `/var/lib/docker` will be stored in that volume rather than the
Docker image being built (i.e., the built image won't have any inner containers
preloaded in it).

As an example, avoid using the `docker:19-dind` image as the base image in the
system container Dockerfile, because this image [implicitly mounts a volume](https://github.com/docker-library/docker/blob/master/19.03/dind/Dockerfile)
over the container's `/var/lib/docker` directory.

For example, this will **not work**:

```dockerfile
FROM docker:19-dind
COPY docker-pull.sh /usr/bin
RUN chmod +x /usr/bin/docker-pull.sh && docker-pull.sh && rm /usr/bin/docker-pull.sh
```

If you build this image (e.g., `docker built -t my-image .`), you'll see that
the resulting image builds properly, but it won't have any inner containers
preloaded in it (i.e., the inner containers pulled by the `docker-pull.sh`
script end up in the host volume that backs `/var/lib/docker`, rather than in
the container image itself).

If you want to use the `docker:19-dind` image and preload it with inner
containers, create a new image by copying it's [Dockerfile](https://github.com/docker-library/docker/blob/master/19.03/dind/Dockerfile)
and removing the `VOLUME /var/lib/docker` line from it. You can then
preload inner containers into that new image with:

```dockerfile
FROM new_image
COPY docker-pull.sh /usr/bin
RUN chmod +x /usr/bin/docker-pull.sh && docker-pull.sh && rm /usr/bin/docker-pull.sh
```

## Committing A System Container That Includes Inner Container Images

**Check out this [video](https://asciinema.org/a/SeinIdpOJBxuDvSf2cGS4NvHZ?speed=2).**

Below are the steps:

1.  Deploy a system container, start dockerd within it, and
    pull some images inside:

```console
$ docker run --runtime=sysbox-runc -it --rm nestybox/alpine-docker

/ # dockerd > /var/log/dockerd.log 2>&1 &

/ # docker image ls
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE

/ # docker pull busybox
Using default tag: latest
latest: Pulling from library/busybox
7c9d20b9b6cd: Pull complete
Digest: sha256:fe301db49df08c384001ed752dff6d52b4305a73a7f608f21528048e8a08b51e
Status: Downloaded newer image for busybox:latest

/ # docker pull alpine
Using default tag: latest
latest: Pulling from library/alpine
89d9c30c1d48: Pull complete
Digest: sha256:c19173c5ada610a5989151111163d28a67368362762534d8a8121ce95cf2bd5a
Status: Downloaded newer image for alpine:latest
```

2.  From the host, let's use the outer Docker to "commit" the system container image:

```console
$ docker ps
CONTAINER ID        IMAGE                    COMMAND             CREATED             STATUS              PORTS               NAMES
31b9a7975749        nestybox/alpine-docker   "/bin/sh"           54 seconds ago      Up 52 seconds                           zen_mirzakhani

$ docker commit zen_mirzakhani nestybox/syscont-with-inner-containers:latest
sha256:82686f19cd10d2830e9104f46cbc8fc4a7d12c248f7757619513ca2982ae8464
```

The commit operation may take several seconds, depending on how many changes
were done in the container's files since it was created.

3.  Create a system container using the committed image, and verify the inner
    images are there:

```console
$ docker run --runtime=sysbox-runc -it --rm nestybox/syscont-with-inner-containers:latest

/ # rm -f /var/run/docker.pid
/ # rm -f /run/docker/containerd/containerd.pid

/ # dockerd > /var/log/dockerd.log 2>&1 &

/ # docker image ls
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
alpine              latest              965ea09ff2eb        3 days ago          5.55MB
busybox             latest              19485c79a9bb        7 weeks ago         1.22MB
```

There they are!

A few restrictions apply here:

-   Committing a system container with **running** inner containers does not
    currently work. That is, the system container being committed can have inner
    container images, but not running inner containers. This is a limitation
    that we will work to remove soon.

-   The `docker commit` instruction takes a `--pause` option which
    is set to `true` by default. Do not set it to `false`; it won't work.

-   The `docker commit` instruction does not capture the contents of volumes or
    bind mounts mounted into the system container. Thus, for the commit to work,
    we must not run the system container with a volume or bind mount onto
    `/var/lib/docker`.

Finally, in the example above, we manually removed the `/var/run/docker.pid` and
`/run/docker/containerd/containerd.pid` files prior to starting the Docker
instance inside the committed system container. This was done because the
Docker commit captures the pid files of the inner Docker and containerd. If
we don't remove these stale files, the inner Docker daemon in the committed
container may fail to start and report errors such as:

```console
Error starting daemon: pid file found, ensure docker is not running or delete /var/run/docker.pid
```

or

```console
Failed to start containerd: timeout waiting for containerd to start
```

Note that such a failure does not occur when the system container has
Systemd inside, as the Systemd service scripts take care of ensuring the
Docker daemon starts correctly regardless of whether the docker.pid file is
present or not.
