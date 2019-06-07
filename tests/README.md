This directory contains tests to verify sysvisor as a whole (i.e.,
sysvisor-runc + sysvisor-fs + sysvisor-mgr).

The tests are organized according to the functionality they test,
rather than the sysvisor components. There are subdirectories
associated with each such functionality.

Some test invoke sysvisor directly, some invoke it via higher level
tools (e.g., Docker, K8s, etc.)

See the Sysvisor [README](https://github.com/nestybox/sysvisor/blob/master/README.md) file for info on how to run these tests.

**Note**: these test differ from the integration tests in the
sysvisor-runc source tree in that those tests focus on sysvisor-runc
and test it in isolation (without sysvisor-fs and sysvisor-mgr).
