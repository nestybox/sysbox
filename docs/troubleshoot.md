Notes on Sysvisor Troubleshooting
=================================

# Troubleshoot a failing sysvisor-runc integration test

* sysvisor-runc integration tests use `bats` inside a privileged docker container.

* bats provides some info regarding the failure, but it's usually not
  enough to pin-point the problem. Sometimes a manual repro is
  required.

* To do the manual repro, follow these steps:

1) In the failing test, add a sleep at the point of interest. E.g.,:

```
@test "runc run [bind mount source path] " {

  # test: bind mount source path has something in common with rootfs path
  run mkdir bindSrc
  [ "$status" -eq 0 ]

  run touch bindSrc/test-file
  [ "$status" -eq 0 ]

  CONFIG=$(jq '.mounts |= . + [{"source": "bindSrc", "destination": "/tmp/bind", "options": ["bind"]}] | .process.args = ["ls", "/tmp/bind/"]' config.json)
  echo "${CONFIG}" >config.json

  # DEBUG
  sleep 1h

  runc run test_bind_mount
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ 'test-file' ]]
}
```

2) From the host, run the failing test via the sysvisor-runc `make integration` target:

```
make integration TESTPATH=/mounts.bats
```

This will launch the privileged container, invoke bats and run the desired test. The test will then be in the wait state.

3) Enter the privileged container:

```
docker exec -it <priv-container-id> /bin/bash
```

**NOTE** Enter the container using `docker exec`; do not enter it with
`nsenter` because the latter won't setup the environment in the
process that enters the container, and this will cause the following
steps to fail.


Next steps are inside the privileged container.

4) Optional: create a symlink for sysvisor-runc

```
ln -s /go/src/github.com/opencontainers/runc/sysvisor-runc /bin/runc
```

5) go to the test directory where the sys container bundle is located:

```
cd /root/busyboxtest
```

6) Execute runc manually as needed to repro. E.g.,:

```
runc --no-sysvisor-mgr --no-sysvisor-fs run test
```
