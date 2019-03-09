# What is this directory?

This directory contains tests to verify system container
functionality as well as interaction between sysvisor-runc
and Docker.

These test differ from the integration tests in the sysvisor-runc
source tree in that those tests focus on sysvisor-runc and test it in
isolation, while these tests focus on system containers and use
Docker to spawn the system containers.

# Requirements

1) The "bats" test framework must be installed on the host:

```
$ git clone https://github.com/sstephenson/bats.git
$ cd bats
$ sudo ./install.sh /usr/local
```

See https://github.com/sstephenson/bats for more info.

2) sysvisor-runc must be installed on the host. From
   the sysvisor-runc source tree, do:

```
$ make && sudo make install
```

3) Docker must be installed on the host, and configured with:

   * User namespace mappings (i.e., `userns-remap`)
   * The sysvisor-runc runtime
   * An image store on a partition with btrfs.

   For example, in my host I created a user called `sysvisor`
   for the user namespace remapping. I also have a disk
   with btrfs mounted at `/mnt/extra1/`. My docker daemon
   config file looks as follows:

```
$ more /etc/docker/daemon.json
{
   "userns-remap": "sysvisor",
   "data-root": "/mnt/extra1/var/lib/docker",
   "runtimes": {
        "sysvisor-runc": {
            "path": "/usr/local/sbin/sysvisor-runc"
        }
    }
}
```

After configuring the docker daemon, it must be re-started:

```
$ sudo systemctl restart docker.service
```

4) Finally, make sure you have access to the Nestybox image repo on
   DockerHub; some of the tests use Docker system container images in
   that repo.

```
$ docker login nestybox
```


# Testing

Run all tests in a test-file using:

```
$ bats --tap test.bats
```

Or run all tests in a directory using:

```
$ bats --tap testDir
``
