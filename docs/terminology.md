Nestybox Project Terminology
============================

# Hosts

__Physical Host__

- A bare-metal run-time environment (hw + linux kernel).


__Virtual Host__

- An isolated run-time environment normally assigned a subset of the
  physical host resources.

- E.g., a VM is a virtual host created through hardware-level virtualization

- E.g., a container is a virtual host created through OS-level virtualization


__Host__

- A host (physical or virtual)


# Resources

__System resource__

- A resource of a host.

- A resource could be hardware

    - E.g.: cpu bandwidth, memory allocation, IO bandwidth, IO devices, etc.

- A resource could be software

    - E.g.: files, pids, users, ip addresses, etc.


__Physical Host Resource__

- A system resource of the physical host.


__Virtual Host Resource__

- A system resource of a virtual host.

- In VMs, virtual host resources are virtualized using
  hardware level virtualization.

- In containers, virtual host resources are virtualized
  using linux kernel namespaces and cgroups.


__Namespaced resource__

- A system resource for which the linux kernel supports namespacing.


__Non-Namespaced resource__

- A system resource for which the linux kernel does not support
  namespacing.


# Namespaces

__Namespace__

- "A namespace wraps a host resource in an abstraction that makes it
  appear to the processes within the namespace that they have their
  own isolated instance of the resource ... One use of namespaces is
  to implement containers". [1]

- Linux currently supports several namespaces (mnt, net, ipc, user,
  uts, pid, cgroup).

- A single namespace may isolate a number of resources (e.g., the
  net namespace isolates ip addresses, ports, iptables, etc).

- Namespaces of the same type have ancestral or sibling
  relationships to each other.

- Note: not all system resources are namespaced.


__Root namespace__

- The initial namespace of a given type.

- The root namespace encompasses all system resources associated
  with the namespace in the physical host.

  - E.g., the pid root namespace encompasses the id's of all
    processes in the physical host.

  - E.g., the net root namespace contains the networking
    config of the physical host.

  - E.g., the user root namespace encompasses the user id for all
    users in the physical host.

- For namespaces that support descendant namespaces (e.g.,
  pid ns, user ns), the root namespace is the oldest ancestor.

  - E.g., the root pid namespace is the oldest ancestor of all other
    pid namespaces.

  - E.g., the root user namespace is the oldest ancestor of all other
    user namespaces.



# Containers

__Container__

- An abstraction that provides processes with a virtual host (see
  virtual host definition).

- Implemented in Linux with namespaces and cgroups.


__Parent container__

- A container inside of which "child" containers are created.

- May have one or more children.


__Child container__

- A container created inside another container.

- Has a single parent container.


__Ancestor container__

- A container that holds an ancestry relationship (parent,
  grand-parent, etc) to one or more containers.


__Descendant container__

- A container that holds a descendancy relationship (child,
  grand-child, etc) to one or more containers.


__Sibling container__

- Two or more containers that have the same parent container.


__Container context__

- The subset of all system resources accessible to a container.

  - Resources governed by namespaces (mounts, pid, network config, etc.)

  - Resources governed by resource controls (e.g., cgroups,
    capabilities, SELinux, AppArmo, etc.)


__App container__

- A container whose main purpose is to run an application.

- For cloud native applications, app containers are typically
  non-persistent and ephemeral (short lifetimes).

- An app container does *not* spawn child containers.


__System container__

- A system container is a container whose main purpose is to package and
  deploy a full operating system environment (e.g., init process, system
  daemons, libraries, utilities, etc.)

- A system container provides enviroment inside of which application
  containers can be deployed (e.g., by running Docker and Kubernetes
  inside the system container).

- A system container presents a more complete abstraction of a virtual
  host to its processes compared to an app container (i.e., a larger
  portion of system resources are exposed).

- Typically has longer life-time than an app container.

- May be stateless or require some persistent state to be stored in
  the host in between executions (via volume mounts).


# Root User

__Root__

- Refers to the root user in a Linux user namespace.


__True root__

- Refers to the root user in the root user namespace.


# Run level

__Process run level (aka level)__

- We define a process run level as:

    Level 0: the process runs directly on the host (not inside a container)

    Level 1: the process runs in a container with no ancestors

    Level 2: the process runs in a container with 1 ancestor

    Level 3: the process runs in a container with 2 ancestors

    And so on ...

- It's easy to think via an analogy to elevators: level 0 is the
  host, level 1 is the first container, level 2 is a
  container inside level 1, and so on.

__Container level__

- A container whose processes run at a given level.

- E.g., "container at level 1" means a container whose processes run
  at level 1 (i.e., a container with no ancestors)


# References

[1] man namespaces(7)
