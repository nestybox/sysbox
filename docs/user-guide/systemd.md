# Sysbox User Guide: Systemd-in-Docker

## Contents

-   [Intro](#intro)
-   [Systemd-in-Docker](#systemd-in-docker)
-   [Systemd Alternatives](#systemd-alternatives)

## Intro

System containers can act as virtual host environments running multiple
services.

As such, including a process manager inside the container such as Systemd is
useful (e.g., to start and stop services in the appropriate sequence, perform
zombie process reaping, etc.)

Moreover, many applications rely on Systemd in order to function properly (in
particular legacy (non-cloud) applications, but also cloud-native software such
as Kubernetes). If you want to run these in a container, Systemd must be present
in the container.

## Systemd-in-Docker

Sysbox has preliminary support for running Systemd inside a system container,
meaning that Systemd works but there are still some minor issues that need
resolution.

With Sysbox, you can run Systemd-in-Docker easily and securely, without the need
to create complex Docker run commands or specialized image entrypoints, and
without resorting to privileged Docker containers.

Simply launch a system container image that has Systemd as its entry point and
Sysbox will ensure the system container is setup to run Systemd without
problems.

You can find examples of system container images that come with Systemd in
the Sysbox repo's [dockerfiles](../../sys-container/dockerfiles). The [Nestybox Dockerhub repo](https://hub.docker.com/u/nestybox) has a number
of these images too.

The Sysbox Quick Start Guide has a [few examples](../quickstart/systemd.md#deploy-a-system-container-with-systemd-inside)
on how to use them.

Of course, the container image will also need to have the systemd service units
that you need. These service units are typically added to the image during the
image build process. For example, the [Dockerfile](../../sys-container/dockerfiles/ubuntu-bionic-systemd-docker/Dockerfile)
for the `nestybox/ubuntu-bionic-systemd-docker` image includes Docker's systemd
service unit by simply installing Docker in the container. As a result, when you
launch that container, Systemd automatically starts Docker.

## Systemd Alternatives

Systemd is great but may be a bit too heavy for your use case.

In that case you can use lighter-weight process managers such as
[Supervisord](http://supervisord.org/).

You can find examples in the Sysbox repo's [dockerfiles](../../sys-container/dockerfiles). The [Nestybox Dockerhub repo](https://hub.docker.com/u/nestybox)
has a number of system container images that come with Supervisord inside.

The Sysbox Quick Start Guide has a [few examples](../quickstart/dind.md#deploy-a-system-container-with-supervisord-and-docker-inside)
on how to use them.
