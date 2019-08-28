# Changelog
All notable changes to this project will be documented in this file.

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
