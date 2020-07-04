# Changelog
All notable changes to this project will be documented in this file.

## [0.2.0] - 2020-07-03
### Added
  * Added initial Kubernetes-in-Docker support to enable secure, flexible and portable K8s clusters.
  * Implemented inner Docker Image Sharing feature, to dramatically reduce host storage utilization for system containers that come preloaded with Docker images.
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
