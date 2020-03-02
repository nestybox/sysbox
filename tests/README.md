Sysbox Integration Tests
========================

This directory contains tests to verify sysbox as a whole (i.e.,
sysbox-runc + sysbox-fs + sysbox-mgr).

The tests are organized according to the functionality they test,
rather than the sysbox components. There are subdirectories
associated with each such functionality.

Some test invoke sysbox directly, some invoke it via higher level
tools (e.g., Docker, K8s, etc.)

See the Sysbox [README](../README.md) file for info on how to run these tests.

**Note**: these test differ from the integration tests in the
sysbox-runc source tree; those tests focus on sysbox-runc
and test it in isolation (without sysbox-fs and sysbox-mgr).
