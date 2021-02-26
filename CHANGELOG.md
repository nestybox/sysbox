# Changelog
All notable changes to this project will be documented in this file.

## [0.3.0] - 2021-02-23
### Added
  * Secured system container initial mounts (mount/remount/unmounts on these from within the container are now restricted). See [here](docs/user-guide/security.md#initial-mount-immutability) for details.
  * Improved Sysbox systemd service unit files (dependencies, open-file limits).
  * Improved logging by sysbox-mgr and sysbox-fs (json logging, more succint logs).
  * Added support for systemd-managed cgroups v1 on the host (cgroups v2 still not supported).
  * Added support for read-only Docker containers.
  * Synced-up sysbox-runc to include the latest changes from the OCI runc.
  * Added ground-work to support Sysbox on RedHat, Fedora, and CentOS (next step is creating a package manager for these).
  * Added config option to configure the Sysbox work directory (defaults to /var/lib/sysbox).
  * Added support and required automation for Sysbox-in-Docker deployments.
  * Fixed sysbox-mgr file descriptor leak (sysbox issue #195).
  * Fixed problem with "docker --restart" on Sysbox containers (sysbox issue #184).
  * Fixed race condition in sysbox-fs procfs & sysfs emulation.
  * Fixed problem preventing kernel-headers from being properly imported within sys containers.
  * Fixed inappropriate handling of mount instructions in chroot jail environments.
### Removed
  * None.

## [0.2.1] - 2020-08-25
### Added
  * Created debian packages for first community-edition release.
  * Fixed package installer bug preventing 'shiftfs' feature from being properly utilized.
  * Enhanced package installer to prevent network overlaps between inner and outer containers.
### Removed
  * Deprecated support of Ubuntu's EOL release: Eoan (19.10).

## [0.2.0] - 2020-07-03
### Added
  * Added initial Kubernetes-in-Docker support to enable secure, flexible and portable K8s clusters.
  * Added support for running privileged-containers within secure system containers.
  * Added support for containerd to run within system containers.
  * Made multiple performance improvements to expedite container initialization and i/o operations.
  * Added support for Ubuntu-Eoan (19.10) and Ubuntu-Focal (20.04).
  * Extended support for Ubuntu-Cloud releases (Bionic, Eoan, Focal).
  * Enhanced Sysbox documentation.
### Removed
  * Deprecated support of Ubuntu's EOL releases: Ubuntu-Disco (19.04) and Ubuntu-Cosmic (18.10).

## [0.1.2] - 2019-11-11
### Added
  * Created Sysbox Quick Start Guide document (with several examples on how to use system containers).
  * Added support for running Systemd in a system container.
  * Added support for the Ubuntu shiftfs filesytem (replaces the Nestybox shiftfs).
  * Using `docker build` to create a system container image that includes inner container images.
  * Using `docker commit` to create a system container image that includes inner container images.
  * Added support for mounts over a system container's `/var/lib/docker` (for persistency of inner container images).
  * Made multiple improvements to the Sysbox User's Guide and Design Guide docs.
  * Rebranded 'sysboxd' to 'sysbox'.
### Removed
  * Deprecated Nestybox shiftfs module.

## [0.1.1] - 2019-09-04
### Added
  * Extend installer support to latest Ubuntu kernel (5.0.0-27).

## [0.1.0] - 2019-08-28
### Added
  * Initial public release.
  * Added external documentation: README, user-guide, design-guide, etc.
  * Extend support to Ubuntu-Bionic (+5.x kernel) with userns-remap disabled.
  * Added consistent versioning to all sysboxd components.
  * Increased list of kernels supported by nbox-shiftfs module (refer to nbox-shiftfs module documentation).
  * Add changelog info to the debian package installer.

## [0.0.1] - 2019-07-23
### Added
  * Internal release (non-public).
  * Supports launching system containers with Docker.
  * Supports running Docker inside a system container.
  * Supports exclusive uid(gid) mappings per system container.
  * Supports partially virtualized procfs.
  * Supports docker with or without userns-remap.
  * Supports Ubuntu Disco (with userns-remap disabled).
  * Supports Ubuntu Disco, Cosmic, and Bionic (with userns-remap enabled).
  * Includes the Nestybox shiftfs kernel module for uid(gid) shifting.
