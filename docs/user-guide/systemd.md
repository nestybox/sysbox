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
the [Dockerfiles](https://github.com/nestybox/dockerfiles) repository. The
Nestybox [Dockerhub repo](https://hub.docker.com/u/nestybox) and
[GitHub Container Registry](https://github.com/orgs/nestybox/packages) have
a number of these images too.

The Sysbox Quick Start Guide has a [few examples](../quickstart/systemd.md#deploy-a-system-container-with-systemd-inside)
on how to use them.

Of course, the container image will also need to have the systemd service units
that you need. These service units are typically added to the image during the
image build process. For example, the [Dockerfile](https://github.com/nestybox/dockerfiles/blob/main/ubuntu-bionic-systemd-docker/Dockerfile)
for the `nestybox/ubuntu-bionic-systemd-docker` image includes Docker's systemd
service unit by simply installing Docker in the container. As a result, when you
launch that container, Systemd automatically starts Docker.

## Unsupported Systemd Services

The great majority of systemd services work well inside system container
deployed with Sysbox.

However, the following services are known not to work:

### systemd-journald-audit.socket

This service pulls audit logs from the kernel and enters them into the systemd
journal. It fails inside the container because it does not have permission to
access the kernel's audit log.

Note that this log is currently a system-wide log, so accessing inside the
container may not be appropriate anyway.

### systemd-udev-trigger.service

This services monitors device events from the kernel's udev subsystem. It fails
inside the container because it does not have the required permissions.

This service is not needed inside a system container, as devices exposed in the
container are setup when the container is started and are immutable
(i.e., hot-plug is not supported).

### systemd-networkd-wait-online.service

This service waits for all network devices to be online. For some
yet-to-be-determined reason, this service is failing inside a system container.

Note that the service is usually not required, given that the container's
network interfaces are virtual and are thus normally up and running when the
container starts.

## Disabling Systemd Services

To disable systemd services inside a container, the best approach is to
modify the Dockerfile for the container and add a line such as:

```
RUN systemctl mask systemd-journald-audit.socket systemd-udev-trigger.service systemd-firstboot.service systemd-networkd-wait-online.service
```

See this [example](https://github.com/nestybox/dockerfiles/blob/master/archlinux-systemd/Dockerfile).

## Systemd Alternatives

Systemd is great but may be a bit too heavy for your use case.

In that case you can use lighter-weight process managers such as
[Supervisord](http://supervisord.org/).

You can find examples in the [Dockerfiles](https://github.com/nestybox/dockerfiles) repository. The
[Nestybox Dockerhub repo](https://hub.docker.com/u/nestybox) has a number of system container
images that come with Supervisord inside.

The Sysbox Quick Start Guide has a [few examples](../quickstart/dind.md#deploy-a-system-container-with-supervisord-and-docker-inside)
on how to use them.
