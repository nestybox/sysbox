Sysvisor Development: Handy Commands
====================================

## Manually spawn sysvisor-runc test container

```
$ docker run  -it --privileged --rm -v /lib/modules:/lib/modules:ro -v /mnt/extra1/chino-dev/nestybox/sysvisor/sysvisor-runc:/go/src/nestybox/sysvisor-runc runc_dev:master /bin/bash
$ root@3aa9dca439e2:/go/src/nestybox/sysvisor-runc# bats -t tests/integration
```

To run single test:

```
$ root@3aa9dca439e2:/go/src/nestybox/sysvisor-runc# bats -t tests/integration/cgroups.bats
```
