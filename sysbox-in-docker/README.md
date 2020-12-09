# Sysbox-In-Docker

As its name implies, Sysbox-In-Docker aims to provide a containerized environment
where to execute the Sysbox runtime.

The goal is to offer a simple and non-invasive environment where users can quickly
interact with the Sysbox runtime. Note that, for the general use-case, Sysbox is
expected to operate in a regular (non-containerized) environment (i.e., host
installation).

## Requirements

There are a few requirements that must be satisfied for Sysbox to properly operate
in a containerized environment:

* Supported Distros: As it's the case for the regular host-based installation,
Sysbox is currently only supported in the distributions shown in this
[doc](../docs/distro-compat.md).

* Root-privileges: As a container runtime, Sysbox requires root privileges to
operate. As a result, Sysbox-In-Docker container must be launched in "privileged"
mode.

    **Note**: Within the privileged container, inner containers launched with Docker +
    Sysbox will be strongly isolated from the host by Sysbox (e.g., via the Linux
    user-namespace).

* Required bind-mounts:

    - "/var/lib/docker"

    - "/var/lib/sysbox"

    - "/lib/modules/<kernel>"

    - "/usr/src/linux-headers-<kernel>"


## Execution

Sysbox-In-Docker environment can be created in three simple steps:

1) Pick the Linux distribution on which to run Sysbox by choosing one of the
Makefile targets displayed below.

    ```
    $ make sysbox-in-docker
    ...
    Usage:
    make sysbox-in-docker <distro-release>

    help                       Show supported docker images
    centos-8                   Build CentOS-8 docker image
    debian-buster              Build Debian-Buster docker image
    debian-bullseye            Build Debian-Bullseye docker image
    fedora-31                  Build Fedora-31 docker image
    fedora-32                  Build Fedora-32 docker image
    ubuntu-bionic              Build Ubuntu-Bionic docker image
    ubuntu-focal               Build Ubuntu-Focal docker image
    $
    ```

2) Build the Sysbox-In-Docker image by executing the chosen target. Notice that
the precise instruction to utlize to launch the Sysbox-In-Docker container will
be displayed as part of this output.

    ```
    $ make sysbox-in-docker ubuntu-bionic
    ...
    *** Launch container with the following instruction ***

    docker run -it --privileged --rm --hostname sysbox-in-docker --name sysbox-in-docker -v /var/tmp/sysbox-var-lib-docker:/var/lib/docker -v /var/tmp/sysbox-var-lib-sysbox:/var/lib/sysbox -v /lib/modules/5.4.0-48-generic:/lib/modules/5.4.0-48-generic:ro -v /usr/src/linux-headers-5.4.0-48-generic:/usr/src/linux-headers-5.4.0-48-generic:ro -v /usr/src/linux-headers-5.4.0-48:/usr/src/linux-headers-5.4.0-48:ro nestybox/sysbox-in-docker:ubuntu-bionic

    make: Nothing to be done for 'ubuntu-bionic'.
    $
    ```

3) Create a Sysbox-In-Docker container by making use of the instruction obtained
in the previous step:

    ```
    $ docker run -it --privileged --rm --hostname sysbox-in-docker --name sysbox-in-docker -v /var/tmp/sysbox-var-lib-docker:/var/lib/docker -v /var/tmp/sysbox-var-lib-sysbox:/var/lib/sysbox -v /lib/modules/5.4.0-48-generic:/lib/modules/5.4.0-48-generic:ro -v /usr/src/linux-headers-5.4.0-48-generic:/usr/src/linux-headers-5.4.0-48-generic:ro -v /usr/src/linux-headers-5.4.0-48:/usr/src/linux-headers-5.4.0-48:ro nestybox/sysbox-in-docker:ubuntu-bionic
    ...
    ```

    In a separate terminal do ...

    ```
   $ docker exec -it sysbox-in-docker bash
   #
    ```
