Sysboxd Integration Tests
==========================

This directory contains tests to verify sysboxd as a whole (i.e.,
sysbox-runc + sysbox-fs + sysbox-mgr).

The tests are organized according to the functionality they test,
rather than the sysboxd components. There are subdirectories
associated with each such functionality.

Some test invoke sysboxd directly, some invoke it via higher level
tools (e.g., Docker, K8s, etc.)

See the Sysboxd [README](../README.md) file for info on how to run these tests.

**Note**: these test differ from the integration tests in the
sysbox-runc source tree; those tests focus on sysbox-runc
and test it in isolation (without sysbox-fs and sysbox-mgr).
