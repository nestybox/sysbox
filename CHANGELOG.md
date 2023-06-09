# Changelog
All notable changes to this project will be documented in this file.

## [0.6.2] - 2023-06-09
### Added
  * Fix bug in Sysbox's checking of host support for idmapping and shiftfs.
  * Fix storage leak in /var/lib/sysbox when using Sysbox on K8s clusters.
  * Fix bug in Sysbox's handling of "docker run -w" flag.
  * Change disable-inner-image-preload flag to allow running (but not committing) sysbox containers with preloaded inner images.
  * Set disable-inner-image-preload flag in Sysbox K8s deployments to improve performance when stopping pods.

## [0.6.1] - 2023-04-07
### Added
  * Added support for ID-mapped overlayfs lower layers; eliminates need for shiftfs and Sysbox rootfs chown; requires kernel 5.19+.
  * Have Sysbox perform shiftfs and ID-mapping functional checks during init (issue #596).
  * Fixed rootfs cloning to prevent inode leakage (for hosts with kernel < 5.19 and no shiftfs) (issue #570).
  * Added support for Kubernetes v1.24 to v1.26.
  * Added --disable-inner-image-preload flag to sysbox-mgr (speeds up Sysbox container startup).
  * Added --syscont-mode flag to sysbox-mgr; allows Sysbox to work in system container mode (default) or regular container mode; the latter is meant for running microservices with stronger isolation.
  * Added --disable-shiftfs-on-fuse flag to sysbox-mgr; prevents Sysbox from mounting shiftfs on top of FUSE-backed filesystems (some of which don't work with shiftfs).
  * Added few optimizations to expedite I/O operations in procfs/sysfs emulated resources.
  * Enhanced life-cycle management of Sysbox daemons in Systemd-free scenarios.
  * Prevented concurrent execution of Sysbox daemons (multi-instance problem).
  * Improved the handling of ungraceful shutdown scenarios.
  * Eliminated Sysbox dependencies on configfs kernel module presence.
  * Fixed emulation of /sys/module/nf_conntrack/parameters inside containers.
  * Added emulation of /sys/devices/virtual/dmi branch inside containers (for hosts where this or inner resources is not present).
  * Hide /sys/kernel/security inside containers (issue #662)
  * Don't assign more capabilities to the container than those given to Sysbox itself.
  * Don't fail in kernel distros without /lib/modules/<kernel-release>.
  * Increased the pods-per-node limit from 16 to 4K (Sysbox-CE now matches Sysbox-EE on this regard).
  * Extended kubelet config-detection process to multiple drop-in files in sysbox-deploy-k8s daemon-set.
  * Incorporated taints during sysbox-deploy-k8s installation process.
  * Fixed issue preventing sysbox-deploy-k8s installation in rke2 environments (issue #614).
  * Fixed issue preventing proper sysbox-deploy-k8s installation in Azure (issue #612).

## [0.5.2] - 2022-05-18
### Added
  * Fixed issue #544 preventing containers initialization within sysbox containers when running latest oci-runc releases (1.1.0-rc.1+).

## [0.5.1] - 2022-04-06
### Added
  * Added support to allow CIFS mounts within Sysbox containers (Sysbox-EE only).
  * Fixed issue to allow shiftfs mounts over files that are themselves bind-mounts.

## [0.5.0] - 2022-03-22
### Added
  * Added support for Linux ID-mapped mounts (shiftfs alternative in kernels >= 5.12).
  * Added support for ARM64 hosts.
  * Added support for running buildx/buildkit inside Sysbox containers.
  * Added support for running Rancher RKE2 and Mirantis K0s inside Sysbox containers.
  * Added configs to disable trapping chown and xattr* syscalls (improves performance but may reduce functionality).
  * Added config to strictly honor container capabilities from higher-level container manager.
  * Added support for per-container configs via `SYSBOX_*` env vars.
  * Improved performance of Sysbox's syscall interception code.
  * Improved the way Sysbox releases the seccomp-fd handles for intercept syscalls (kernels >= 5.8).
  * Improved Sysbox's cross-compilation support (artifacts can now be generated from/to either AMD64 or ARM64 hosts).
  * Update to golang 1.16.
  * Replaced the per-distro *.deb installation packages with a single deb bundle package.
  * Allow alternative Docker data-root inside a Sysbox container (if Docker is pre-installed in the Sysbox container image).
  * Fixed segfault when building Docker image inside Sysbox container (issue #484).
  * Fixed segfault when running python pip install inside nested sysbox container (issue #485).
  * Fixed issue with running KinD inside a Sysbox container (issue #415).
  * Fixed problem with shiftfs mounts on Kubernetes persistent volumes (issue #431).

### Removed
  * None.

## [0.4.1] - 2021-09-30
### Added
  * Added important optimization to expedite the container creation cycle.
  * Enhanced uid-shifting logic to perform shifting operations of Sysbox's special dirs on a need basis.
  * Added support for Kinvolk's Flatcar Linux distribution (Sysbox-EE only).
  * Added basic building-blocks to allow Sysbox support on ARM platforms.
  * Fixed issue preventing Sysbox folders from being eliminated from HDD when Sysbox is shutdown.
  * Enable sys container processes to set 'trusted.overlay.opaque' xattr on files (issue #254).
  * Fixed bug resulting in the failure of "mount" operation within a sys container.
  * Made various enhancements to Sysbox's kubernetes installer to simplify its operation.
  * Extend Sysbox's kubernetes installer to support Rancher's RKE k8s distribution.

## [0.4.0] - 2021-07-13
### Added
  * Added support to create secure Kubernetes PODs with Sysbox (sysbox-pods).
  * Added support for Cgroups-v2 systems.
  * Added support to allow K3s execution within Sysbox containers.
  * Extended Sysbox support to Fedora-33 and Fedora-34 releases.
  * Extended Sysbox support to Flatcar Linux distribution.
  * Modified Sysbox binaries' installation path ("/usr/local/sbin" -> "/usr/bin").
  * Enhanced generation and handling of logging output by relying on systemd (journald) subsystem.
  * Multiple enhancements in /proc & /sys file-system's emulation logic.
  * Extended installer to allow it to deploy Sysbox in non-strictly-supported distros / releases.
  * Improved security of shiftfs mounts.
  * Fixed issue impacting sysbox-fs stability in scaling scenarios (issue #266).
  * Fixed issue preventing sys-container initialization due a recent change in oci-runc (issue #291).
  * Fixed issue with "--mountpoint" cli knob being ignored (sysbox issue #310).
  * Fixed issue causing sysbox-fs handlers to stall upon access to a procfs node (issue #306).
  * Fixed issue preventing write access to 'domainname' procfs node (issue #287).
  * Fixed issue preventing systemd-based containers from being able to initialize (issue #273).
  * Made changes to allow Docker network sharing between containers.
  * Ensure that Sysbox mounts in read-only containers are mounted as read only.
### Removed
  * Deprecated EOL'd Fedora-31 and Fedora-32 releases.

## [0.3.0] - 2021-03-26
### Added
  * Secured system container initial mounts (mount/remount/unmounts on these from within the container are now restricted). See [here](docs/user-guide/security.md#initial-mount-immutability) for details.
  * Improved Sysbox systemd service unit files (dependencies, open-file limits).
  * Improved logging by sysbox-mgr and sysbox-fs (json logging, more succint logs).
  * Added support for systemd-managed cgroups v1 on the host (cgroups v2 still not supported).
  * Added support for read-only Docker containers.
  * Synced-up sysbox-runc to include the latest changes from the OCI runc.
  * Added support for Debian distribution (Buster and Bullseye).
  * Added ground-work to support Sysbox on RedHat, Fedora, and CentOS (next step is creating a package manager for these).
  * Added config option to configure the Sysbox work directory (defaults to /var/lib/sysbox).
  * Added support and required automation for Sysbox-in-Docker deployments.
  * Fixed sporadic session stalling issue during syscall interception handling.
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

## [0.0.1] - unreleased
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
