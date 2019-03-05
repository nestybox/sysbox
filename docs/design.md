Sysvisor Design Notes
=====================

The document describes the design of sysvisor.

# General

Sysvisor is a container runtime specifically built to run system
containers.

Sysvisor's main role is to setup and manage the system container's
runtime environment.

# System Containers

Refer to the system container spec (sysContainer.md).

# Architecture

Sysvisor is comprised on 2 main components:

* sysvisor-runc: fork of the OCI runc, customized for running system containers.

* sysvisor-fs: FUSE-based filesystem, handles emulation of ceratain
  files in the system container's rootfs.

sysvisor-runc is the frontend for sysvisor; higher layers (e.g.,
Docker or Kubernetes via containerd) invoke sysvisor-runc to
launch system containers.

sysvisor-fs is the backend for sysvisor; it handles emulation of
certain files in the system container's rootfs, in particular
some files under /proc and /sys.

Communication between sysvisor-runc and sysvisor-fs is done
via gRPC.

# System container OCI config requirements & overrides


TODO: move some of this to the system container spec doc.   <<< HERE



The following are requirements that Sysvisor places on the OCI spec
for a system container.

Whenever these conflict with the OCI spec, we clearly mention this.

In cases where the system container spec does not meet these
requirements, depending on the specific config Sysvisor may
bail (with an informative error) or override the config when
spawning the container (with an appropriate log message).

## Init Process

* Sysvisor honors the init process selected for the
  system container via the spec's Process object.

* Normally, we expec that the init process in a system
  container will be an init daemon (e.g., systemd). But
  that's not always true, and Sysvisor does require this.

## Capabilities

* Sysvisor gives the system container's root process (uid = 0) is
  full capabilities, regardless of what the system container's
  spec indicates.

  - This applies to processes that enter the system container via any
    of the defined entry points (i.e., `sysvisor-runc run` or
    `sysvisor-runc exec`).

* A non-root process (uid != 0) is given the capabilities as follows:

  - If entering the system container via the `sysvisor-runc run` or
    `sysvisor-runc exec` commands, it gets the capabilities defined
    in the spec; if none are defined, it gets no capabilities.

  - If created inside the system container (clonned from a sys
    container process), it gets capabilities per Linux rules
    (see capabilities(7)).


## uid/gid mappings

* The system container's spec must have uid/gid mappings.

* It must map a range >= 65536 starting at uid 0, to support running most
  Linux distros inside a system container.

  - E.g., Debian uses uid 65534 as "nobody".

* Note: Sysvisor does not require that the container's rootfs
  uid/gid owner match the host uid/gid in the spec. If these don't
  match, some files will show up as "nobody:nogroup" inside the system
  container. Some runc tests use such mappings.

## Namespaces

* The system container spec must include the following namespaces:

  - user
  - pid
  - ipc
  - uts
  - mount
  - network

* The system container spec may optionally include the
  following namespaces; if not present, Sysvisor will add them.

  - cgroup

* Note: Docker meets these requirements when configured with the
  "userns-remap" option.

## Cgroups

* The system container's cgroup is read-writable, to allow a root
  process in the system container to create cgroups.

  - This functionality is needed to run system software such as Docker
    or Systemd inside the system container.

* However, we want to prevent a root process in the system container
  from changing the cgroup resources assigned to the system container
  itself. To do this, Sysvisor creates two cgroup directories
  for each system container on the host:

  `/sys/fs/cgroup/<controller>/<syscont-id>/`
  `/sys/fs/cgroup/<controller>/<syscont-id>/syscont-cgroup-root/`

* The first directory is not exposed inside the container; it's
  configured with the resources assigned to the system container.
  The system container has no visibility and permissions for it.

* The second directory is exposed inside the system container.
  Sysvisor gives root in the system container full access to it
  (mounts it read-write as the system container's cgroup root,
  and changes the ownership on the host to match the system
  container's root process).

* In addition, Sysvisor uses the cgroup namespace to hide the host
  path for the cgroup root inside the system container.

## Read-only paths

* Sysvisor will honor read-only paths in the system container
  spec, except when these correspond to paths managed by
  sysvisor-fs.

  - The rationale is that sysvisor-fs paths are required for system
    container operation; thus sysvisor-fs decides whether to
    how to expose the path.

  - This may change in the future as use cases arise.

## Masked paths

* Sysvisor will honor masked paths in the system container
  spec, except when these correspond to paths managed by
  sysvisor-fs.

  - The rationale is that sysvisor-fs paths are required for system
    container operation; thus sysvisor-fs decides whether to
    how to expose the path.

  - This may change in the future as use cases arise.

## Readonly rootfs

## Pre-start hooks

## Seccomp


# sysvisor-fs File Emulation


# User/Group ID Allocation & Mapping


# Rootless mode

Sysvisor will initially not support running rootless (i.e.,
without root permissions on the host).

In the future we should consider adding this to allow regular
users on a host to launch system containers.


# Systme container security

## AppArmor
