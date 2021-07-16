# Sysbox Developer's Guide: Testing

## Contents

-   [Intro](#intro)
-   [Running the entire suite](#running-the-entire-suite)
-   [Running the Sysbox integration tests only](#running-the-sysbox-integration-tests-only)
-   [Running the unit tests](#running-the-unit-tests)
-   [More on Sysbox integration tests](#more-on-sysbox-integration-tests)
-   [The Test Shell](#the-test-shell)
-   [Test cleanup](#test-cleanup)

## Intro

The Sysbox test suite is made up of the following:

* Unit tests: written with Go's "testing" package.

* Integration tests: written using the [bats](https://github.com/sstephenson/bats) framework.

All tests run inside a privileged Docker container (i.e., Sysbox as well as the
tests that exercise it execute inside that container).

## Running the entire suite

To run the entire Sysbox test suite:

```
$ make test
```

This command runs all test targets (i.e., unit and integration
tests).

## Running the Sysbox integration tests only

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

Or to run one specific handler test:

```
$ make test-sysbox TESTPATH=tests/sysfs/disable_ipv6.bats
```

## Running the unit tests

To run unit tests for one of the Sysbox components (e.g., sysbox-fs, sysbox-mgr, etc.)

```
$ make test-runc
$ make test-fs
$ make test-mgr
```

## More on Sysbox integration tests

The Sysbox integration Makefile target (`test-sysbox`) spawns a
Docker privileged container using the image in tests/Dockerfile.[distro].

It then mounts the developer's Sysbox directory into the privileged
container, builds and starts Sysbox *inside* of it, and runs the
tests in directory `tests/`.

These tests use the ["bats"](https://github.com/nestybox/sysbox/blob/master/README.md)
test framework, which is pre-installed in the privileged container
image.

In order to launch the privileged container, Docker must be present in the host
and configured without userns-remap (as userns-remap is not compatible with
privileged containers). In other words, make sure the `/etc/docker/daemon.json`
file is not configured with the `userns-remap` option prior to running the
Sysbox integration tests.

## The Test Shell

In order to debug, it's very useful to launch the Docker privileged container
and get a shell in it. This can be done with:

```
$ make test-shell
```

or

```
$ make test-shell-shiftuid
```

The former command configures Docker inside the test container in userns-remap
mode.  The latter command configures docker inside the privileged test container
without userns remap, thus forcing Sysbox to use uid-shifting via the shiftfs
module.

From within the test shell, you can deploy a system container as usual:

```
# docker run --runtime=sysbox-runc -it nestybox/ubuntu-bionic-system-docker
```

Or you can run a test with:

```
# bats -t tests/integration/cgroups.bats
```

## Test cleanup

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
