# What is this directory?

This directory contains tests to verify sysvisor as a whole
(i.e., sysvisor-runc + sysvisor-fs).

Some test invoke sysvisor directly, some invoke it via
higher level tools (e.g., Docker, K8s, etc.)

These test differ from the integration tests in the sysvisor-runc
source tree in that those tests focus on sysvisor-runc and test it in
isolation (without sysvisor-fs).

## Requirements

### 1) The "bats" test framework must be installed on the host:

```
$ git clone https://github.com/sstephenson/bats.git
$ cd bats
$ sudo ./install.sh /usr/local
```

See https://github.com/sstephenson/bats for more info.

### 2) sysvisor-runc and sysvisor-fs must be installed on the host.

From the `nestybox/sysvisor` directory, type:

```
$ make && sudo make install
```

### 3) Docker must be installed on the host.

Docker must be installed and configured with:

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

### 4) sysvisor-fs must be running

```
$ sudo sysvisor-fs /var/lib/sysvisor-fs > /run/log/sysvisor-fs.log 2>&1
```

### 5) Make sure that Docker is logged-in to the Nestybox repo on Dockerhub

Some of the tests use Docker system container images in that repo.

```
$ docker login nestybox
```


# Running Tests

After the above requirements are met, run tests using the Makefile in
`nestybox/sysvisor` as follows:

```
make sysvisortest
```

Or run a specific test file as follows:

```
make sysvisortest TESTPATH=/nestedDocker.bats
```
