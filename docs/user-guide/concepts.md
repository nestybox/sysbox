# Sysbox User Guide: Concepts & Terminology

These document describes concepts and terminology used by the Sysbox container
runtime. We use these throughout our documents.

## Contents

-   [Container Runtime](#container-runtime)
-   [Container Manager](#container-manager)
-   [System Container](#system-container)
-   [Inner and Outer Containers](#inner-and-outer-containers)
-   [Docker-in-Docker (DinD)](#docker-in-docker-dind)
-   [Kubernetes-in-Docker (KinD)](#kubernetes-in-docker-kind)

## Container Runtime

The software that given the container's configuration and root filesystem
(i.e., a directory that has the contents of the container) interacts with the
Linux kernel to create the container.

Sysbox and the [OCI runc](https://github.com/opencontainers/runc) are examples
of container runtimes.

The entity that provides the container's configuration and root filesystem to
the container runtime is typically a container manager
(e.g., Docker, containerd).

## Container Manager

The container manager manages the container's lifecycle, from image transfer and
storage to container execution (by interacting with the container runtime).

Examples are Docker, containerd, etc.

The [OCI runtime spec](https://github.com/opencontainers/runtime-spec) describes
the interface between the container manager and the container
runtime.

## System Container

A container that is capable of executing system-level software such as Docker,
Kubernetes, Systemd, etc., with proper isolation (i.e., without privileged
containers) and without using complex container images or entrypoints.

Traditionally, containers package a single application / micro-service. This
makes sense for application containers, where multiple such containers form the
application and separation of concerns is important.

However, system containers deviate from this a bit: they are meant to be used as
light-weight, super-efficient "virtual hosts", and thus typically bundle
multiple services.

Within the system container you can run the services of your choice (e.g.,
Systemd, sshd, Docker, etc.), and even launch (inner) containers just as you
would on a physical host of VM. You can think of it as a **"virtual host"** or a
**"container of containers"**.

Of course, you can package a single service (e.g., Docker daemon) if you so
desire; the choice is yours.

System containers provide an alternative to VMs in many scenarios, but are much more
**flexible, efficient, and portable**. They offer strong isolation (in fact stronger than
regular Docker containers) but to a lesser degree than the isolation provided by a VM.

For more info on system containers, see this [blog article](https://blog.nestybox.com/2019/09/13/system-containers.html).

Sysbox is a container runtime that creates system containers.

## Inner and Outer Containers

When launching Docker inside a system container, terminology can
quickly get confusing due to container nesting.

To prevent confusion we refer to the containers as the "outer" and
"inner" containers.

-   The outer container is a system container, created at the host
    level; it's launched with Docker + Sysbox.

-   The inner container is an application container, created within the outer
    container (e.g., it's created by the Docker or Kubernetes instance running
    inside the system container).

## Docker-in-Docker (DinD)

DinD refers to deploying Docker (CLI + Daemon) inside Docker containers.

Sysbox supports DinD using well-isolated (unprivileged) containers and without
the need for complex Docker run commands or specialized images.

## Kubernetes-in-Docker (KinD)

KinD refers to deploying Kubernetes inside Docker containers.

Each Docker container acts as a K8s node (replacing a VM or physical host).

A K8s cluster is composed of one or more of these containers, connected via an
overlay network (e.g., Docker bridge).

Sysbox supports KinD with high efficiency, using well-isolated (unprivileged)
containers, and without the need for complex Docker run commands or specialized
images.
