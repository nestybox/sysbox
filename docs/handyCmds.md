Sysboxd Development: Handy Commands
====================================

## Manually spawn sysbox-runc test container

```
$ docker run  -it --privileged --rm -v /lib/modules:/lib/modules:ro -v /mnt/extra1/chino-dev/nestybox/sysboxd/sysbox-runc:/go/src/nestybox/sysbox-runc runc_dev:master /bin/bash
$ root@3aa9dca439e2:/go/src/nestybox/sysbox-runc# bats -t tests/integration
```

To run single test:

```
$ root@3aa9dca439e2:/go/src/nestybox/sysbox-runc# bats -t tests/integration/cgroups.bats
```

## Kill a process group

```
pstree -g | less -i
pkill -9 -g <process-group>
```
