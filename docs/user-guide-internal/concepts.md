# Sysbox Iternal User Guide: Concepts & Terminology

## Hosts

### Physical Host

-   A bare-metal run-time environment (hw + linux kernel).

### Virtual Host

-   An isolated run-time environment normally assigned a subset of the
    physical host resources.

-   E.g., a VM is a virtual host created through hardware-level virtualization

-   E.g., a container is a virtual host created through OS-level virtualization

### Host

-   A host (physical or virtual)

## Resources

### System resource

-   A resource of a host.

-   A resource could be hardware

    -   E.g.: cpu bandwidth, memory allocation, IO bandwidth, IO devices, etc.

-   A resource could be software

    -   E.g.: files, pids, users, ip addresses, etc.

### Physical Host Resource

-   A system resource of the physical host.

### Virtual Host Resource

-   A system resource of a virtual host.

-   In VMs, virtual host resources are virtualized using
    hardware level virtualization.

-   In containers, virtual host resources are virtualized
    using linux kernel namespaces and cgroups.

### Namespaced resource

-   A system resource for which the linux kernel supports namespacing.

### Non-Namespaced resource

-   A system resource for which the linux kernel does not support
    namespacing.

## Namespaces

### Namespace

-   "A namespace wraps a host resource in an abstraction that makes it
    appear to the processes within the namespace that they have their
    own isolated instance of the resource ... One use of namespaces is
    to implement containers". [1]

-   Linux currently supports several namespaces (mnt, net, ipc, user,
    uts, pid, cgroup).

-   A single namespace may isolate a number of resources (e.g., the
    net namespace isolates ip addresses, ports, iptables, etc).

-   Namespaces of the same type have ancestral or sibling
    relationships to each other.

-   Note: not all system resources are namespaced.

### Root namespace

-   The initial namespace of a given type.

-   The root namespace encompasses all system resources associated
    with the namespace in the physical host.

    -   E.g., the pid root namespace encompasses the id's of all
        processes in the physical host.

    -   E.g., the net root namespace contains the networking
        config of the physical host.

    -   E.g., the user root namespace encompasses the user id for all
        users in the physical host.

-   For namespaces that support descendant namespaces (e.g.,
    pid ns, user ns), the root namespace is the oldest ancestor.

    -   E.g., the root pid namespace is the oldest ancestor of all other
        pid namespaces.

    -   E.g., the root user namespace is the oldest ancestor of all other
        user namespaces.

## Containers

### Container

-   An abstraction that provides processes with a virtual host (see
    virtual host definition).

-   Implemented in Linux with namespaces and cgroups.

### Parent container

-   A container inside of which "child" containers are created.

-   May have one or more children.

### Child container

-   A container created inside another container.

-   Has a single parent container.

### Ancestor container

-   A container that holds an ancestry relationship (parent,
    grand-parent, etc) to one or more containers.

### Descendant container

-   A container that holds a descendancy relationship (child,
    grand-child, etc) to one or more containers.

### Sibling container

-   Two or more containers that have the same parent container.

### Container context

-   The subset of all system resources accessible to a container.

    -   Resources governed by namespaces (mounts, pid, network config, etc.)

    -   Resources governed by resource controls (e.g., cgroups,
        capabilities, SELinux, AppArmo, etc.)

### App container

-   A container whose main purpose is to run an application.

-   For cloud native applications, app containers are typically
    non-persistent and ephemeral (short lifetimes).

-   An app container does _not_ spawn child containers.

### System container

-   See [here](https://github.com/nestybox/nestybox/blob/master/tech/system-containers.md).

-   A system container presents a more complete abstraction of a virtual
    host to its processes compared to an app container (i.e., a larger
    portion of system resources are exposed inside the container).

-   Typically has longer life-time than an app container.

-   May be stateless or require some persistent state to be stored in
    the host in between executions (via volume mounts).

## Root User

### Root

-   Refers to the root user in a Linux user namespace.

### True root

-   Refers to the root user in the root user namespace.

## Run level

### Process run level (aka level)

-   We define a process run level as:

      Level 0: the process runs directly on the host (not inside a container)

      Level 1: the process runs in a container with no ancestors

      Level 2: the process runs in a container with 1 ancestor

      Level 3: the process runs in a container with 2 ancestors

      And so on ...

-   It's easy to think via an analogy to elevators: level 0 is the
    host, level 1 is the first container, level 2 is a
    container inside level 1, and so on.

### Container level

-   A container whose processes run at a given level.

-   E.g., "container at level 1" means a container whose processes run
    at level 1 (i.e., a container with no ancestors)
