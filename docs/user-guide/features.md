# Sysbox User Guide: Feature List

## OCI-based

-   Integrates with OCI compatible container managers (e.g., Docker).

-   Currently we only support Docker/containerd, but plan to add support for
    more managers / orchestrators (e.g., K8s) soon.

-   Sysbox is ~90% OCI-compatible. See [here](design.md#sysbox-oci-compatibility) for
    more on this.

## Systemd-in-Docker [ v0.1.2+ ]

-   Run Systemd inside a Docker container easily, without complex container configurations.

-   Enables you to containerize apps that rely on Systemd (e.g., legacy apps).

## Docker-in-Docker

-   Run Docker inside a container easily and without insecure privileged containers.

-   Full isolation between the Docker inside the container and the Docker on the host.

## Kubernetes-in-Docker [ v0.2.0+ ]

-   Deploy Kubernetes (K8s) inside containers with proper isolation (no
    privileged containers), using simple Docker images and Docker run commands
    (no need for custom Docker images with tricky entrypoints).

-   Deploy directly with `docker run` commands for full flexibility, or using a
    higher level tool (e.g., such as [kindbox](https://github.com/nestybox/kindbox)).

## Strong container isolation

-   Root user in the system container maps to a fully unprivileged user on the host.

-   The procfs and sysfs exposed in the container are fully namespaced.

-   Programs running inside the system container (e.g., Docker, Kubernetes, etc)
    are limited to using the resources given to the system container itself.

-   The system container's initial mounts are immutable (can't be changed from
    inside the container, even though processes in the container can setup
    other mounts).

-   See the [security section](security.md) of the User Guide
    for details.

## Fast & Efficient

-   Sysbox uses host resources optimally and starts containers in a few seconds.

## Inner Container Image Preloading

-   You can create a system container image that includes inner container
    images using a simple Dockerfile or via Docker commit. See [here](../quickstart/images.md) for more.

Please see our [Roadmap](../../README.md#roadmap) for a list of features we are working on.
