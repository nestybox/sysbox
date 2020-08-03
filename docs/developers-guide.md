# Sysbox Developer's Guide

## Contents

-   [Thanks for Contributing](#thanks-for-contributing)
-   [Cloning the Sysbox Repo](#cloning-the-sysbox-repo)
-   [Setting up your Development Environment](#setting-up-your-development-environment)
-   [Building & Installing from Source](#building--installing-from-source)
-   [Sysbox Testing](#sysbox-testing)
-   [Usage](#usage)
-   [Troubleshooting](#troubleshooting)
-   [Debugging](#debugging)

## Thanks for Contributing

Thanks for contributing to Sysbox, we much appreciate it. Please read our
[contribution guidelines](../CONTRIBUTING.md) before submitting a pull-request.

## Cloning the Sysbox Repo

```
git clone https://github.com/nestybox/sysbox.git
```

## Setting up your Development Environment

TODO: make this simpler by doing the build in a container and outputing the result.

In order to build Sysbox, your machine's OS must be one of those
[supported by Sysbox](docs/distro-compat.md).

In addition, you the following software installed:

* Golang

* Docker

* Make and autoconf utilities

* gRPC protoc compiler

The [setupDevEnvDeb](bin/setupDevEnvDeb) script can install this software for you.

## Building & Installing from Source

Once you have setup your development environment, you build Sysbox with:

```
$ make sysbox
$ sudo make install
```

Launch Sysbox with:

```
$ sudo bin/sysbox
```

This launches the sysbox-fs and sysbox-mgr daemons. The daemons will log into
`/var/log/sysbox-fs.log` and `/var/log/sysbox-mgr.log` (these logs are useful
for troubleshooting).

## Sysbox Testing

The Sysbox test suite is made up of the following:

* sysbox-mgr unit tests
* sysbox-fs unit tests
* sysbox-runc unit and integration tests
* sysbox integration tests (these test all components together)

All tests run inside a privileged Docker container (i.e., Sysbox as well as the
tests that exercise it execute inside that container).

### Running the entire suite

To run the entire Sysbox test suite:

```
$ make test
```

This command runs all test targets (i.e., unit and integration
tests).

### Running the Sysbox integration tests only

Without uid-shifting:

```
$ make test-sysbox
```

With uid-shifting:

```
$ make test-sysbox-shiftuid
```

It's also possible to run a specific integration test with:

```
$ make test-sysbox TESTPATH=<test-name>
```

For example, to run all sysbox-fs handler tests:

```
$ make test-sysbox TESTPATH=tests/sysfs
```

Or to run one specific hanlder test:

```
$ make test-sysbox TESTPATH=tests/sysfs/disable_ipv6.bats
```

### Running the unit tests

To run unit tests for one of the Sysbox components (e.g., sysbox-fs, sysbox-mgr, etc.)

```
$ make test-runc
$ make test-fs
$ make test-mgr
```

### More on Sysbox integration tests

The Sysbox integration Makefile target (`test-sysbox`) spawns a
Docker privileged container using the image in tests/Dockerfile.

It then mounts the developer's Sysbox directory into the privileged
container, builds and installs Sysbox *inside* of it, and runs the
tests in directory `tests/`.

These tests use the ["bats"](https://github.com/nestybox/sysbox/blob/master/README.md)
test framework, which is pre-installed in the privileged container
image.

In order to launch the privileged container, Docker must be present in
the host and configured without userns-remap (as userns-remap is not
compatible with privileged containers). Make sure the
`/etc/docker/daemon.json` file is not configured with the
`userns-remap` option prior to running the Sysbox integration tests.

Also, in order to debug, it's sometimes useful to launch the Docker
privileged container and get a shell in it. This can be done with:

```
$ make test-shell
```

or

```
$ make test-shell-shiftuid
```

The latter command configures docker inside the privileged test
container without userns remap, thus forcing Sysbox to use
uid-shifting.

From within the test shell, run a test with:

```
# bats -t tests/integration/cgroups.bats
```

### Test cleanup

The test suite creates directories on the host which it mounts into
the privileged test container. The programs running inside the
privileged container (e.g., docker, sysbox, etc) place data in these
directories.

The Sysbox test targets do not cleanup the contents of these
directories so as to allow their reuse between test runs in order to
speed up testing (e.g., to avoid having the test container download
fresh docker images between subsequent test runs).

Instead, cleanup of these directories must be done manually via the
following make target:

```
$ sudo make test-cleanup
```

The target must be run as root, because some of the files being
cleaned up were created by root processes inside the privileged test
container.

## Usage

Refer to the Sysbox [Usage docs](https://github.com/nestybox/sysbox-external/blob/master/docs/usage.md).

## Troubleshooting

Refer to the Sysbox [troubleshooting notes](docs/troubleshoot.md).

## Debugging

Refer to the Sysbox [debugging notes](docs/debug.md)
for detailed information on the sequence of steps required to debug
Sysbox modules.

## Uninstalling

```
$ sudo make uninstall
$ make clean
```
