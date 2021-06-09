# Sysbox User Guide: Feature List

## OCI-based

-   Integrates with OCI compatible container managers and orchestrators (e.g., Docker and Kubernetes).

-   Sysbox is ~90% OCI-compatible. See [here](design.md#sysbox-oci-compatibility) for
    more on this.

## Easy Installation

-   Installs easily on Docker hosts or Kubernetes clusters.

-   For Kubernetes clusters, installation is done via a daemonset.

-   See [here](install.md) for more.

## Strong container isolation

-   Always enables the Linux user-namespace on all containers:

    - Root user in the system container has all capabilities inside container
      only, but zero privileges on the host.

-   The procfs and sysfs exposed in the container are fully namespaced.

-   Programs running inside the system container (e.g., Docker, Kubernetes, etc)
    are limited to using the resources given to the system container itself.

-   The system container's initial mounts are immutable (can't be changed from
    inside the container, even though processes in the container can setup
    other mounts).

-   See the [security section](security.md) of the User Guide
    for details.

## Systemd-in-Docker [ v0.1.2+ ]

-   Run Systemd inside a Docker container or K8s pod easily, without complex
    container configurations.

-   Enables you to containerize apps that rely on Systemd (e.g., legacy apps).

## Docker-in-Docker

-   Run Docker inside a container or pod, easily without insecure privileged
    containers and without mounting the host's Docker socket.

-   Full isolation between the Docker inside the container and the Docker on the
    host.

-   The inner Docker container images can live ephemerally inside the container
    or be cached on the host.

## Kubernetes-in-Docker [ v0.2.0+ ]

-   Use containers as Kubernetes nodes, instead of more expensive VMs.

-   Containers are properly isolated (via the Linux user namespace) and run
    Kubernetes natively (as a VM or regular host would); no custom Docker images
    or tricky entrypoints needed.

-   Deploy directly with `docker run` commands for full flexibility, or using a
    higher level tool (e.g., such as [kindbox](https://github.com/nestybox/kindbox)).

-   Alternatively, run the K8s.io KinD tool inside a Sysbox container to containerize
    and entire Kubernetes cluster for local testing, and with proper isolation.

## Fast & Efficient

-   Sysbox uses host resources optimally and starts containers in a few seconds.

-   Runs with performance equivalent to the OCI runc.

-   See [here](https://blog.nestybox.com/2020/09/23/perf-comparison.html) for a
    detailed performance analysis.

## Inner Container Image Preloading

-   You can create a system container image that includes inner container
    images using a simple Dockerfile or via Docker commit. See [here](../quickstart/images.md) for more.

Please see our [Roadmap](../../README.md#roadmap) for a list of features we are working on.
