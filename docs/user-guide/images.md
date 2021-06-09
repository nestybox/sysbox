# Sysbox User Guide: System Container Images

## Contents

-   [Intro](#intro)
-   [Nestybox Dockerhub Repo](#nestybox-dockerhub-repo)
-   [Preloading Inner Container Images into a System Container \[ v0.1.2+ \]](#preloading-inner-container-images-into-a-system-container--v012-)
-   [Approaches to Image Preloading](#approaches-to-image-preloading)
-   [Preloading Inner Container Images with Docker Build](#preloading-inner-container-images-with-docker-build)
-   [Preloading Inner Container Images with Docker Commit](#preloading-inner-container-images-with-docker-commit)
-   [Inner Docker Image Sharing](#inner-docker-image-sharing)

## Intro

This document describes aspects of System Container images.

The most important point: system container images are regular Docker
images. There is nothing special about them.

They usually carry system software in them (e.g., Systemd, Docker, K8s, etc.), but
can carry application software too.

You normally don't need any special or customized entrypoints in the system
container images. And you don't need complex Docker run commands to deploy them.

That's because the Sysbox runtime does the heavy lifting of ensuring that the
software in the image runs correctly inside the container.

Since system container images often include Docker in them, it is useful
to preload inner container images inside the system container. Sysbox makes this
very easy. See [below](#preloading-inner-container-images-into-a-system-container--v012-) for info on
how to do this.

## Nestybox Dockerhub Repo

The [Nestybox Dockerhub repo](https://hub.docker.com/u/nestybox) has several images that
we provide as reference for users.

We often use these in the examples we provide in this User-Guide and [Quickstart guide](../quickstart/README.md).

The Dockerfiles are [here](https://github.com/nestybox/dockerfiles). Feel free to copy them and adapt them to
your needs.

If you see an error on them or think they can be improved, please file a [GitHub issue](../../CONTRIBUTING.md).

## Preloading Inner Container Images into a System Container \[ v0.1.2+ ]

Sysbox allows you to easily preload inner container images into a system container image.

This has several benefits:

-   Improves performance:

    -   If your system container is always deploying a common set of inner
        containers, you avoid the need for each system container to pull those from
        the network every time. Depending on the size of the inner image, it can
        significantly improve performance.

-   Ease of use:

    -   It's easier to deploy a system container that comes preloaded with your choice
        of inner containers than to pull those inner containers into system container
        at runtime.

-   Air-gapped environments:

    -   In environments where there is no network connection, preloading the system
        container with inner container is a must have.

***
#### ** --- Sysbox-EE Feature Highlight --- **

In addition, Sysbox Enterprise Edition (Sysbox-EE) has a feature called "Inner
Docker Image Sharing" that maximizes sharing of preloaded inner container images
across system containers. This **significantly** reduces the storage overhead on
the host. See the section on [Inner Docker Image Sharing](#inner-docker-image-sharing)
below for more details.

***

## Approaches to Image Preloading

There are two ways preload inner container into a system container image:

-   Using `docker build`

-   Using `docker commit`

Both of these are described in the sections below.

## Preloading Inner Container Images with Docker Build

You can use a simple Dockerfile to preload inner container images into a system
container image.

Conceptually, the process is simple: the Dockerfile for the system container
image has an instruction that requests the container manager inside the system
container (e.g., inner Docker) to pull the inner container images. That's it.

There is a [step-by-step example](../quickstart/images.md#building-a-system-container-that-includes-inner-container-images--v012-)
in the Sysbox Quick-Start Guide.

This process also works if the system container image has containerd inside
(rather than Docker). In this case, the Dockerfile must request containerd
to pull the inner images.

We use this feature often. For example, the [Dockerfile](https://github.com/nestybox/dockerfiles/blob/main/k8s-node/Dockerfile)
for the `k8s-node` image (used for running Kubernetes-in-Docker) preloads the Kubernetes pod images using
this same approach.

## Preloading Inner Container Images with Docker Commit

You can also use `docker commit` to preload inner container images into
a system container image.

It's helpful as a way of saving work or exporting a working system container for
deployment in another machine (i.e., commit the image, docker push to a repo,
and docker pull from another machine).

The approach is also very simple: launch a system container that has an inner
Docker, use the inner Docker to pull the inner images, and then commit the
system container with the outer Docker. The committed image will include
the inner Docker images.

There is a [step-by-step example](../quickstart/images.md#committing-a-system-container-that-includes-inner-container-images)
in the Quick-Start Guide.

This approach is helpful as a way of saving work or exporting a working system
container for deployment in another machine (i.e., commit the system container
image, docker push to a repo, and docker pull from another machine).

***
#### ** --- Sysbox-EE Feature Highlight --- **

## Inner Docker Image Sharing

One of the side-effects of preloading inner container images is that the system
container images can quickly grow in size (typically hundreds of MBs).

To make matters worse, when the system container is created using that image,
Sysbox is forced to allocate more storage on the host in order to bypass
limitations associated with overlayfs nesting (i.e., overlayfs is the filesystem
used by Docker to create the container's filesystem).

For example, if a system container image is preloaded with inner Docker images
totaling a size of 500MB, each system container instance would normally require
that Sysbox allocate 500MB of storage on the host. If you deploy 10 system
containers, the overhead is 5GB. If you deploy 100 system containers, it grows
to 50GB. And so on. You get the point: the overhead can quickly grow.

To mitigate this, Sysbox-EE has a feature called "inner Docker image sharing" that
**significantly** reduces the storage overhead. This feature works by ensuring
that multiple system containers created from the same image share preloaded
inner Docker image layers using Copy-on-Write (COW).

Continuing with the prior example, this feature allows you to deploy any number
of system containers and still only use 500MB of storage overhead for the
preloaded inner images! In other words, the storage overhead for preloaded inner
Docker images goes from O(n) to O(1), where 'n' is the number of system
containers.

Inner Docker image sharing is one of the key features that make Sysbox-EE a very
efficient container runtime for deploying Docker or Kubernetes inside
containers.

As another example, see this storage overhead [table](../quickstart/kind.md#why-sysbox-for-k8s-in-docker)
for running Kubernetes in Docker containers with Sysbox vs Sysbox-EE.

### Effects on Container Startup Time

Inner Docker image sharing also improves the system container startup time.

The reason is that this feature causes Sysbox to move less data around when the
system container starts.

However, this improvement does not take effect on the first system
container instance based off a given image, but only on subsequent system
container instances based off the same image.

For example, the `nestybox/k8s-node` image is a system container used for
deploying Kubernetes-in-Docker. This image is preloaded with inner Docker
containers totaling up to 765MB.

When deploying 4 system containers with this image, notice the latency:

```console

cesar@eoan:$ time docker run --runtime=sysbox-runc -d nestybox/k8s-node:v1.18.2
fea256c7dc7dc28e5e4b8bc3a7419888dea99c825b69502545485d76158a678b

real    0m5.858s
user    0m0.027s
sys     0m0.028s


cesar@eoan:$ time docker run --runtime=sysbox-runc -d nestybox/k8s-node:v1.18.2
fc62a96cbb372ee5d16b28b5688ab4d331391fe20baa6add9e8758f6962dde47

real    0m0.991s
user    0m0.038s
sys     0m0.018s


cesar@eoan:$ time docker run --runtime=sysbox-runc -d nestybox/k8s-node:v1.18.2
26d4c94a3398604ea3f473ab6868ad359ffa1e30c5db20cd98922b1cd1591e5c

real    0m1.061s
user    0m0.030s
sys     0m0.027s

cesar@eoan:$ time docker run --runtime=sysbox-runc -d nestybox/k8s-node:v1.18.2
6b886f1c491c6cd593ec46f4f6076126309993add7b6426547283c5c9728da9e

real    0m0.953s
user    0m0.034s
sys     0m0.030s
```

The first system container instance took 5.8 seconds to deploy, and the rest
took ~1 second.

The reason for this is that when creating the first instance, Sysbox had to move
data for the inner container images. For subsequent instances this movement was
not required due to the inner Docker image sharing feature.

### Limitations of Inner Docker Image Sharing

There are a few limitations for inner Docker image sharing:

-   The storage savings apply only for inner container images that are [preloaded into the system container](#preloading-inner-container-images-into-a-system-container--v012-).
    They do not apply for inner images downloaded into the system container at runtime.

-   The storage savings apply only when the inner container images are Docker
    images, and to a lesser extend when they are Containerd images. They do not
    apply when using other container managers inside the system container.

### Disabling Inner Docker Image Sharing

Inner Docker image sharing is enabled by default in Sysbox.  It's possible to
disable it by passing the `--inner-docker-image-sharing=false` flag to the
sysbox-mgr.

See the [User Guide Configuration doc](configuration.md) for further info
on how to do this.

***
