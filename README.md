<p align="center">
    <img alt="sysbox" src="./docs/figures/sysbox_community_edition.png"/>
</p>

<p align="center">
    <a href="https://github.com/nestybox/sysbox/blob/master/LICENSE"><img alt="GitHub license" src="https://img.shields.io/github/license/nestybox/sysbox"></a>
    <a href="https://travis-ci.com/nestybox/sysbox">
    <img src="https://img.shields.io/circleci/project/github/badges/shields/master" alt="build status"></a>
    <a href="https://nestybox-support.slack.com/join/shared_invite/enQtOTA0NDQwMTkzMjg2LTAxNGJjYTU2ZmJkYTZjNDMwNmM4Y2YxNzZiZGJlZDM4OTc1NGUzZDFiNTM4NzM1ZTA2NDE3NzQ1ODg1YzhmNDQ#">
    <img src="https://img.shields.io/badge/chat-on%20slack-FF3386"></a>
</p>

## Introduction

**Sysbox** is an open-source container runtime (aka runc), originally
developed by [Nestybox](https://www.nestybox.com), that enables Docker
containers to act as virtual servers capable of running software such as
Systemd, Docker, and Kubernetes in them, easily and with proper isolation. This
allows you to use containers in new ways, and provides a
[faster, more efficient, and more portable alternative](https://blog.nestybox.com/2020/09/23/perf-comparison.html)
to virtual machines in many scenarios.

Prior to Sysbox, running such software in a container required you to create
complex images, custom entrypoints, special volume mounts, and use very unsecure
privileged containers. With Sysbox, this is as simple as:

```
$ docker run --runtime=sysbox-runc -it some-image
```

In this container, you can now run Systemd, Docker, Kubernetes, etc., just like
you would on a physical host or virtual machine. You can launch inner containers
(and even inner privileged containers), knowing that the outer container is
strongly isolated from the underlying host (via the Linux user-namespace). No
more complex docker images or docker run commands, and no need for unsecure
privileged containers.

In order to do this, Sysbox uses many OS-virtualization features of the Linux
kernel and complements these with OS-virtualization techniques implemented in
user-space. These include using all Linux namespaces (in particular
the user-namespace), partial virtualization of procfs and sysfs, selective
syscall trapping, and more. Due to this, Sysbox requires a fairly recent Linux
kernel (see the [supported distros](#supported-distros) below).

Sysbox was forked from the excellent OCI runc in early 2019, and has undergone
significant changes since then. It's written in Go, and it is currently composed
of three components: sysbox-runc, sysbox-fs, and sysbox-mgr. More on Sysbox's
design can be found in the [Sysbox user guide](docs/user-guide/design.md).

Sysbox sits below OCI-compatible container managers such as Docker / containerd,
allowing you to use these well known tools to deploy the containers. No need to
learn new tools.

The complete list of features is [here](#sysbox-features).

## Contents

-   [License](#license)
-   [Audience](#audience)
-   [System Containers](#system-containers)
-   [Supported Distros](#supported-distros)
-   [Host Requirements](#host-requirements)
-   [Installing Sysbox](#installing-sysbox)
-   [Using Sysbox](#using-sysbox)
-   [Docker Default Runtime Config](#docker-default-runtime-config)
-   [Documentation](#documentation)
-   [Sysbox Features](#sysbox-features)
-   [Integration with Container Managers & Orchestrators](#integration-with-container-managers--orchestrators)
-   [Sysbox does not use hardware virtualization](#sysbox-does-not-use-hardware-virtualization)
-   [Comparison to related technologies](#comparison-to-related-technologies)
-   [Contributing](#contributing)
-   [Filing Issues](#filing-issues)
-   [Troubleshooting & Support](#troubleshooting--support)
-   [Roadmap](#roadmap)
-   [Relationship to Nestybox](#relationship-to-nestybox)
-   [Uninstallation](#uninstallation)
-   [Contact](#contact)
-   [Thank You](#thank-you)

## License

Sysbox is an open-source project, licensed under the Apache License, Version
2.0. See the [LICENSE](LICENSE) file for details.

## Audience

The Sysbox project is intended for anyone looking to experiment, invent, learn,
and build systems using system containers. It's cutting-edge OS virtualization,
and contributions are welcomed.

The Sysbox project is **not** meant for people looking for a commercially
supported solution. For such a solution, use the **Sysbox Enterprise Edition
(Sysbox-EE)**.

Sysbox-EE uses Sysbox at its core, but complements it with enterprise-level
features for improved security and efficiency as well as Nestybox support
(see next section).

For info on where to find and download Sysbox-EE, refer to the
[Nestybox website](https://www.nestybox.com).

## Sysbox Features

The table below summarizes the key features of the Sysbox container
runtime. It also provides a comparison between the Sysbox Community
Edition (i.e., this repo) and the Sysbox Enterprise Edition
(Sysbox EE).

<p align="center">
    <img alt="sysbox" src="./docs/figures/sysbox-features.png" width="1000x" />
</p>

More on the features [below](#sysbox-feature-description).

If you have questions, you can reach us [here](#contact).

## System Containers

We call the containers deployed by Sysbox **system containers**, to highlight the
fact that they can run not just micro-services (as regular containers do), but
also system software such as Docker, Kubernetes, Systemd, inner containers, etc.

More on system containers [here](docs/user-guide/concepts.md#system-container).

## Supported Distros

Sysbox relies on functionality available only in relatively recent Linux kernel
releases.

See the [distro compatibility doc](docs/distro-compat.md) for information about
the supported Linux distributions and the required kernel releases.

We plan to add support for more distros in the near future.

## Installing Sysbox

1) Download the latest Sysbox community-edition package from the
[release](https://github.com/nestybox/sysbox/releases) page:

```console
$ wget https://github.com/nestybox/sysbox/releases/download/v0.2.1/sysbox_0.2.1-0.ubuntu-focal_amd64.deb
```

2) Verify that the checksum of the downloaded file fully matches the expected/published one.
   For example:

```console
$ sha256sum sysbox_0.2.1-0.ubuntu-focal_amd64.deb
126e4963755cdca440579d81409b3f4a6d6ef4c6c2d4cf435052a13468e2c250  sysbox_0.2.1-0.ubuntu-focal_amd64.deb
```

3) Stop and eliminate all running Docker containers. Refer to the
[detailed](docs/user-guide/install.md) installation process for information
on how to avoid impacting existing containers.

```
$ docker rm $(docker ps -a -q) -f
```

... if an error is returned, it simply indicates that no existing containers were found.

4) Install the Sysbox package and follow the installer instructions:

```console
$ sudo apt-get install ./sysbox_0.2.1-0.ubuntu-focal_amd64.deb -y
```

More information on the installation process can be found [here](docs/user-guide/install.md). If you
run into problems during installation, see the [troubleshooting doc](docs/user-guide/troubleshoot.md).

Alternatively, you can build Sysbox binaries yourself. It's a very simple process as
we have a 'make' target that builds Sysbox inside a Docker container, and another
'make' target that installs Sysbox on your host. See the
[Sysbox developer's guide](docs/developers-guide/README.md) for more on this.

## Using Sysbox

Once Sysbox is installed, you use it as follows:

```console
$ docker run --runtime=sysbox-runc --rm -it --hostname my_cont debian:latest
root@my_cont:/#
```

This launches a system container. It looks very much like a regular container,
but it's different under the hood. Within it can run application or system-level
software (systemd, dockerd, K8s) inside just as you would in a VM. The container
is strongly isolated via the Linux user-namespace.

The [Sysbox Quickstart Guide](docs/quickstart/README.md) has many usage examples.
You should start there to get familiarized with the use cases enabled by Sysbox.

Note that if you omit the `--runtime` option, Docker will use its default `runc`
runtime to launch regular containers (rather than system containers). It's
perfectly fine to run system containers launched with Docker + Sysbox alongside
regular Docker containers; they won't conflict and can co-exist side-by-side.

## Docker Default Runtime Config

Optionally, you can make Sysbox the default runtime for Docker. To do this, add
the `default-runtime` config to `/etc/docker/daemon.json`. It should look
similar to this:

```
{
  "default-runtime": "sysbox-runc",
  "runtimes": {
     "sysbox-runc": {
        "path": "/usr/local/sbin/sysbox-runc"
     }
  }
}
```

Then restart Docker (e.g., `sudo systemctl restart docker`). With this setup,
you can omit the `--runtime=sysbox-runc` flag when using `docker run` to create
containers with Sysbox.

## Documentation

We strive to provide good documentation; it's a key component of the Sysbox project.

We have several documents to help you get started and get the best out of
Sysbox.

-   [Sysbox Quick Start Guide](docs/quickstart/README.md)

    -   Provides many examples for using system containers. New users
        should start here.

-   [Sysbox User Guide](docs/user-guide/README.md)

    -   Provides more detailed information on Sysbox features and design.

-   [Sysbox Distro Compatibility Doc](docs/distro-compat.md)

    -   Distro compatibility requirements.

-   [Nestybox blog site](https://blog.nestybox.com/)

    -   Articles on using Sysbox to solve real-life problems.

## Sysbox Feature Description

### OCI-based

-   Integrates with OCI compatible container managers (e.g., Docker).

-   Currently we only support Docker/containerd, but plan to add support for
    more managers / orchestrators (e.g., K8s) soon.

-   Sysbox is ~90% OCI-compatible. See [here](docs/user-guide/design.md#sysbox-oci-compatibility) for
    more on this.

### Systemd-in-Docker

-   Run Systemd inside a Docker container easily, without complex container configurations.

-   Enables you to containerize apps that rely on Systemd (e.g., legacy apps).

### Docker-in-Docker

-   Run Docker inside a container easily and without unsecure privileged containers.

-   Full isolation between the Docker inside the container and the Docker on the host.

### Kubernetes-in-Docker

-   Deploy Kubernetes (K8s) inside containers with proper isolation (no
    privileged containers), using simple Docker images and Docker run commands
    (no need for custom Docker images with tricky entrypoints).

-   Deploy directly with `docker run` commands for full flexibility, or using a
    higher level tool (e.g., such as [kindbox](https://github.com/nestybox/kindbox)).

### Strong container isolation

-   Root user in the system container maps to a fully unprivileged user on the host.

-   The procfs and sysfs exposed in the container are fully namespaced.

-   Programs running inside the system container (e.g., Docker, Kubernetes, etc)
    are limited to using the resources given to the system container itself.

-   Avoid the need for unsecure privileged containers.

### Fast & Efficient

-   Sysbox uses host resources optimally and starts containers in a few seconds.

### Inner Container Image Preloading

-   You can create a system container image that includes inner container
    images using a simple Dockerfile or via Docker commit. See [here](docs/quickstart/images.md) for more.

Please see our [Roadmap](#roadmap) for a list of features we are working on.

## Integration with Container Managers & Orchestrators

Though Sysbox is OCI-based (and thus compatible with OCI container managers),
it's currently only tested with Docker / containerd.

In particular, we don't yet support using Kubernetes to deploy system containers
with Sysbox (though we [plan to](#roadmap)).

## Performance

Sysbox is fast and efficient, as described in this [Nestybox blog post](https://blog.nestybox.com/2020/09/23/perf-comparison.html).

The system containers created by Sysbox have have similar performance to those
created by Docker's default runtime (the OCI runc).

Even containers deployed inside the system containers have excellent
performance, thought there is a slight overhead for network IO (as expected
since packets emitted by inner Docker containers go through an additional Docker
network inside the system container).

Now, if you use Sysbox to deploy system containers that replace VMs, then the
performance and efficiency gains are significant: you can deploy twice as many
system containers as VMs on the same server and get the same performance, and do
this with a fraction of the memory and storage consumption. The blog post
referenced above has more on this.

## Sysbox does not use hardware virtualization

Though the containers generated by Sysbox resemble virtual machines in some ways
(e.g., you can run as root, run multiple services, and deploy Docker and K8s
inside), Sysbox does **not** use hardware virtualization. It's purely an
OS-virtualization technology meant to create containers that can run
applications as well as system-level software, easily and securely.

This makes the containers created by Sysbox [very fast, efficient, and portable](https://blog.nestybox.com/2020/09/23/perf-comparison.html).
Isolation wise, it's fair to say that they provide stronger isolation
than regular Docker containers (by virtue of using the Linux user-namespace),
but weaker isolation than VMs (by sharing the Linux kernel among containers).

## Comparison to related technologies

Sysbox is pretty unique: it is, to the best of our knowledge, the only OCI-based
container runtime that allows Docker and similar tools to deploy "VM-like"
containers capable of running systemd, Docker, K8s, etc., with ease and strong
isolation from the underlying host (i.e., no privileged containers).

See this [blog post](https://blog.nestybox.com/2020/10/06/related-tech-comparison.html) for a high-level comparison between Sysbox and related technologies
such as LXD, K8s.io KinD, Ignite, Kata Containers, rootless Docker, and more.

## Contributing

We welcome contributions to Sysbox, whether they are small documentation changes,
bug fixes, or feature additions. Please see the [contribution guidelines](CONTRIBUTING.md)
and [developer's guide](docs/developers-guide/README.md) for more info.

## Filing Issues

We apologize for any problems in Sysbox or its documentation, and we appreciate
people filing issues that help us improve the software.

Please see the [contribution guidelines](CONTRIBUTING.md) for info on how
to report issues.

## Troubleshooting & Support

Refer to the [Troubleshooting document](docs/user-guide/troubleshoot.md)
and to the [issues](https://github.com/nestybox/sysbox/issues) for help.

Reach us at our [slack channel][slack] for any questions.

## Uninstallation

Prior to uninstalling Sysbox, make sure all system containers are removed.
There is a simple shell script to do this [here](scr/rm_all_syscont).

The method for uninstalling Sysbox depends on how you [installed it](#installing-sysbox).

1) If you used the packaged version from the Nestybox website, follow the
   uninstallation instructions in the associated documentation.

2) If you built it from source and installed it manually, follow [these instructions](docs/developers-guide/build.md)
   to uninstall it.

## Roadmap

The following is a list of features in the Sysbox roadmap.

We list these here so that our users can get a better idea of where we
are going and can give us feedback on which of these they like best
(or least).

Here is a short list; the Sysbox issue tracker has many more.

-   Support for more Linux distros.

-   Support for deploying system containers with Kubernetes.

-   More improvements to procfs and sysfs virtualization.

-   Continued improvements to container isolation.

-   Exposing host devices inside system containers with proper permissions.

## Relationship to Nestybox

Sysbox was initially developed by [Nestybox](https://www.nestybox.com), and Nestybox is
the main sponsor of the Sysbox open-source project.

Having said this, we encourage participation from the community to help evolve
and improve it, with the goal of increasing the use cases and benefits it
enables. External maintainers and contributors are welcomed.

Nestybox uses Sysbox as the core of it's Sysbox enterprise product (Sysbox-EE),
which consists of Sysbox plus proprietary features meant for enterprise use.

To ensure synergy between the Sysbox project and commercial entities such as
Nestybox, we use the following criteria when considering adding functionality to
Sysbox:

Any features that mainly benefit individual practitioners are made part of the
Sysbox open-source project. Any features that mainly address enterprise-level
needs are reserved for the Sysbox Enterprise Edition.

The Sysbox project maintainers will make this determination on a feature by
feature basis, with total transparency. The goal is to create a balanced
approach that enables the Sysbox open-source community to benefit and thrive
while creating opportunities for commercial entities to create a healthy viable
business around the technology.

## Contact

Slack: [Nestybox Slack Workspace][slack]

Email: contact@nestybox.com

We are available from Monday-Friday, 9am-5pm Pacific Time.

## Thank You

We thank you **very much** for using and/or contributing to Sysbox. We hope you
find it interesting and that it helps you use containers in new and more powerful
ways.

[slack]: https://nestybox-support.slack.com/join/shared_invite/enQtOTA0NDQwMTkzMjg2LTAxNGJjYTU2ZmJkYTZjNDMwNmM4Y2YxNzZiZGJlZDM4OTc1NGUzZDFiNTM4NzM1ZTA2NDE3NzQ1ODg1YzhmNDQ#/
