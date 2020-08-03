# Sysbox Internal User Guide: Troubleshooting

The customer docs for sysbox contain basic info on
troubleshooting. See [here](../../sysbox-staging/docs/user-guide/troubleshoot.md).

The following is additional troubleshooting information meant for
Nestybox's internal use only.

## Passing debug flags to Sysbox from Docker

sysbox-runc takes several debug flags in its command line. When
invoking sysbox-runc via Docker, these options can be passed down
from Docker to sysbox-runc by adding the `runtimeArgs` clause in the
`/etc/docker/daemon.json` file.

For example, to disable strict checking for kernel version
compatiblity, use:

```json
        {
           "runtimes": {
                "sysbox-runc": {
                    "path": "/usr/local/sbin/sysbox-runc",
                    "runtimeArgs": [
                        "--no-kernel-check"
                    ]
                }
            }
        }
```

Type `sysbox-runc --help` for further info on command line flags.

## Debug a failing sysbox-runc integration test

-   sysbox-runc integration tests use `bats` inside a privileged docker container.

-   bats provides some info regarding the failure, but it's usually not
    enough to pin-point the problem. Sometimes a manual repro is
    required.

-   To do the manual repro, follow these steps:

1) In the failing test, add a sleep at the point of interest. E.g.,:

```console
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

2) From the host, run the failing test via the sysbox-runc `make integration` target:

```console
make integration TESTPATH=/mounts.bats
```

This will launch the privileged container, invoke bats and run the desired test. The test will then be in the wait state.

3) Enter the privileged container:

```console
docker exec -it <priv-container-id> /bin/bash
```

**NOTE** Enter the container using `docker exec`; do not enter it with
`nsenter` because the latter won't setup the environment in the
process that enters the container, and this will cause the following
steps to fail.

Next steps are inside the privileged container.

4) Optional: create a symlink for sysbox-runc

```console
ln -s /go/src/github.com/opencontainers/runc/sysbox-runc /bin/runc
```

5) go to the test directory where the sys container bundle is located:

```console
cd /root/busyboxtest
```

6) Execute runc manually as needed to repro. E.g.,:

```console
runc --no-sysbox-mgr --no-sysbox-fs run test
```

## Watching Sysbox processes in real time

```console
watch -n 0.2 'pstree -SlpgT | grep -A 10 sysbox-fs'
```

## Debugging Networking Issues in Sys Containers

-   Identify the network topology inside the sys container.

    -   Use `ip` to show the interfaces and understand how the relate to each other.

-   Use `tcpdump` to track flow of packets across the sys container the network
    components:


    tcpdump -i <interface> -n

-   The `-n` flag ensures tcpdump does not try to map IP address -> DNS, which
    reduces the noise in the dump.


-   Use `iptables -L -t <table> ` to list the iptables inside the sys container.

    -   The `-v` flag can be added to track the number of packets traversing each
        of the chains. It's helpful to see if packets are traversing the chains
        that one expects them to traverse.

-   When the iptables do DNAT or SNAT, the tcpdump can be a bit hard to read.  You
    must be aware of where the NATing occurs in order to understand the dump.

-   Here are some good resources of iptables:

    <https://www.frozentux.net/iptables-tutorial/chunkyhtml/c962.html>
    <https://www.digitalocean.com/community/tutorials/a-deep-dive-into-iptables-and-netfilter-architecture>
    <https://fedoraproject.org/wiki/How_to_edit_iptables_rules>