System Container Spec
=====================

# Definition

A system container is a container whose main purpose is to package and
deploy a full operating system environment (e.g., init process, system
daemons, libraries, utilities, etc.)

A system container provides enviroment inside of which application
containers can be deployed (e.g., by running Docker and Kubernetes
inside the system container).

Compared to regular containers which are currently used to package and
deploy application micro-services, system containers expose Linux
OS/kernel resources commonly used by cloud infrastructure tools such
as those mentioned above.

Compared to virtual machines, a system container is lighter-weight,
more efficient, and faster to deploy, but provides less isolation from
the underlying host as it shared the kernel with other system
containers.


# Features


# Sample Use Cases


# Comparison to App Containers


# Comparison to VMs
