Nestybox Sysboxd
================

## Introduction

Sysboxd is software that integrates with Docker and allows it to
create system containers.

The customer docs for sysboxd contain a lot of info on installation,
usage, design, etc. Those are found in the [sysboxd external repo](https://github.com/nestybox/sysvisor-external)

This repo contains the source code for sysboxd, as well as additional
docs that are for Nestybox's internal use only.

## Building & Installing from Source

```
$ make sysbox
$ sudo make install
```

Launch Sysboxd with:

```
$ sudo sysbox &
```

This launches the sysbox-fs and sysbox-mgr daemons. The daemons
will log into `/var/log/sysbox-fs.log` and
`/var/log/sysbox-mgr.log` (these logs are useful for
troubleshooting).

## Sysboxd Testing

The Sysboxd test suite is made up of the following:

* sysbox-mgr unit tests
* sysbox-fs unit tests
* sysbox-runc unit and integration tests
* Sysboxd integration tests (these test all components together)

### Running the entire suite

To run the entire Sysboxd test suite:

```
$ make test
```

This command runs all test targets (i.e., unit and integration
tests).

*Note*: This includes Sysboxd integration tests with and without
uid-shifting. Thus the shiftfs module be loaded in the kernel *prior*
to running this command. See above for info on loading shiftfs.

### Running the Sysboxd integration tests only

Without uid-shifting:

```
$ make test-sysboxd
```

With uid-shifting:

```
$ make test-sysboxd-shiftuid
```

It's also possible to run a specific integration test with:

```
$ make test-sysboxd TESTPATH=<test-name>
```

For example, to run all sysbox-fs handler tests:

```
$ make test-sysboxd TESTPATH=tests/sysfs
```

Or to run one specific hanlder test:

```
$ make test-sysboxd TESTPATH=tests/sysfs/disable_ipv6.bats
```

### Running the unit tests

To run unit tests for one of the Sysboxd components (e.g., sysbox-fs, sysbox-mgr, etc.)

```
$ make test-runc
$ make test-fs
$ make test-mgr
```

### shiftfs unit tests

To run the full suite of tests:

```
$ make test-shiftfs
```

To run a single test:

```
$ make test-shiftfs TESTPATH=shiftfs/pjdfstest/tests/open
```

### More on Sysboxd integration tests

The Sysboxd integration Makefile target (`test-sysboxd`) spawns a
Docker privileged container using the image in tests/Dockerfile.

It then mounts the developer's Sysboxd directory into the privileged
container, builds and installs Sysboxd *inside* of it, and runs the
tests in directory `tests/`.

These tests use the ["bats"](https://github.com/nestybox/sysbox/blob/master/README.md)
test framework, which is pre-installed in the privileged container
image.

In order to launch the privileged container, Docker must be present in
the host and configured without userns-remap (as userns-remap is not
compatible with privileged containers). Make sure the
`/etc/docker/daemon.json` file is not configured with the
`userns-remap` option prior to running the Sysboxd integration tests.

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
container without userns remap, thus forcing Sysboxd to use
uid-shifting.

From within the test shell, run a test with:

```
# bats -t tests/integration/cgroups.bats
```

### Testing Shiftfs

We use the [pjdfstest suite](https://github.com/pjd/pjdfstest) to test
shiftfs POSIX compliance.

To run the tests, use:

```
make test-shiftfs
```

This target launches the privileged test container, creates a test
directory, mounts shiftfs on this directory, and runs the pjdfstest
suite.

Make sure to run the test target only on Linux distros in which
shiftfs is supported.

### Test cleanup

The test suite creates directories on the host which it mounts into
the privileged test container. The programs running inside the
privileged container (e.g., docker, sysbox, etc) place data in these
directories.

The Sysboxd test targets do not cleanup the contents of these
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

Refer to the Sysboxd [Usage docs](docs/usage.md).

## Troubleshooting

Refer to the Sysboxd [troubleshooting notes](docs/troubleshoot.md).

## Debugging

Refer to the Sysboxd [debugging notes](docs/debug.md)
for detailed information on the sequence of steps required to debug
Sysboxd modules.
