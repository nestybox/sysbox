System Containers
=================

The customer docs for sysboxd contain a description of system containers.
See [here](https://github.com/nestybox/sysvisor-external/blob/master/docs/system-containers.md).

The following is additional information meant for Nestybox's internal
use only.

## Use cases

* We envision using system containers as alternative to VMs
  (once they acquire sufficient features).

## Comparison to VMs

In some ways, a system container resembles a VM. In particular, both
can be used to package and deploy a complete system environment.

But system containers offer a different set of features & tradeoffs
when compared to VMs. Below are the pros & cons.

System Container Pros:

* Light, fast, and much more efficient than VMs (allowing for improved
  performance and much higher density).

* Flexible: you can configure the system container with the amount of
  software that you want, from a single binary to a full blown system
  with systemd, multiple apps, ssh server, docker, etc.

* Portable: the system container can run on bare-metal or in a
  cloud VM, in a high-end server or low-end device. It's not tied to a
  given hypervisor but rather to Linux (which runs almost everywhere).

* Easy-of-use: the system container can be packaged & deployed with
  Docker or Kubernetes. It voids the need for VM configuration &
  maintenance tools.

System Container Cons:

* It offers reduced isolation compared to a VM (i.e., system
  containers share the Linux kernel while VMs share the hypervisor;
  the attack surface of the former is wider than that of the latter).
  Thus, VMs are better suited for multi-tenant clouds with strict
  security requirements.

* It does not (currently) package hardware dependencies.

* A Linux system container must be deployed on a Linux host. It's not
  possible to deploy it on another platform (e.g., a Windows host).
