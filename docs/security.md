Sysbox Security Guide (Internal)
================================

The customer docs for sysbox info on sysbox's security.
See [here](https://github.com/nestybox/sysbox-staging/blob/master/docs/security.md).

The following is additional design information meant for Nestybox's
internal use only.

**NOTE:** Much of this is work-in-progress, as we've yet to harden
security in Sysbox and system containers.

## Attack Types

* Container escapes (guest-to-host)
* Cross container
* Inner container (gain access of a container through a vulnerability)
* DoS and Resource Consumption
* New code attacks (bugs that lead to vulnerabilities)
* Host container engine / runtime attacks

## NCC Group Recommendation

"When hardening containers, the goal should be to reduce the kernel
attack surface however possible; as the kernel should be strongly
considered a "known unknown". [1]

## Usage Scenarios

* Dev/test
* Production
* Server-side sandboxing
* Clieng-side sandboxing

## System Container Security

### /proc mount

* Partially virtualized & protected by virtue of using user-namespace

* Partially virtualized by sysbox-fs

* Unmounting of `/proc` within the sys container is not possible,
  thanks to the fact that we use the user-ns and that sysbox-fs has
  mounts under it:

  ```
  root@c0ee9f35a9cf:~# umount -f /proc
  umount: /proc: must be superuser to unmount.

  root@c0ee9f35a9cf:~# umount /proc
  umount: /proc: target is busy.
  ```

* Mounting of another `/proc` within the sys container is possible,
  and

* Also, tmpfs mounts over `/proc` is possible. But this only affects
  the sys container processes, no security risk.

### /sys mount

* Read-only

  - Except for `/sys/fs/cgroup`

* Can `/sys` be unmounted inside a container?

### Syscalls

* List of syscalls we restrict

* List of syscalls we allow (compared to Docker)

* Seccomp

  * ptrace syscall must be disabled for seccomp to work; otherwise an attacker can break seccomp.

* FYI: LXC default seccomp profile: blocks

  `kexec_load, open_by_handle_at, init_module, finit_module, and delete_module`

* Syscall trapping

  - Watch out for TOCTOU vulnerability.

  - use seccomp-bpf or eBPF ?

### Mandatory Access Controls (MAC)

* AppArmor

* SELinux

* sysbox doc: no appArmor (or other MAC) solution for now.

### Device Exposure

* Sysbox; indicate which devices we allow; and which we don't.

* sw vs hw devices

### Kernel Info Exposure

* Masked paths

* Readonly paths

* sysbox: dmesg not permitted (good; hides kernel info)

* sysbox: `/proc/kallsyms` exposed.

* sysbox: `/proc/kcore` hidden; good.

* kernel key-ring.

* sysbox: debugfs exposure

* sysbox: /proc/self/mountinfo exposes container rootfs path within host

* sysbox: /sys/kernel/vmcoreinfo exposed

* sysbox: /proc/sys/security exposure

* sysbox: /sys/firmware exposure

* sysbox: hides `/proc/sys/fs/binfmt_misc`

### Resource Limiting & Cgroups

TODO

### Immutable (read-only) Sys Container Support

TODO

### No-new-privileges Support

TODO

### Networking

* Sys containers don't support the "host network namespace".

  - Host network namespace is not compatible with user-namespaces.

## Inner Container Security

* sysbox: security-in-depth by running inner apps within docker containers.

* Uses regular Docker; further restrics capabilities on inner container

## Host Security

* sysbox: by running docker within sys containers, and exposing their API, you avoid
  giving root/docker group privileges to regular users.

## Sysbox Daemon Security

* Runs as host root, so presents a security risk.

* How is sysbox itself secured?

* gRPC security

* sysbox-mgr & sysbox-fs sockets

* appArmor profile for sysbox

* Sysbox isolated from container (no mounts to allow container to
  communicate with Sysbox).

## "Rootless Docker" vs. System Containers

Docker has an experimental "rootless" mode in which the Docker daemon
on the host runs without root privileges on the host.

It's an approach that seeks to accomplish the benefits described in
the prior section, but using a different method than the one used by
Nestybox system containers.

We briefly describe it here to shed a bit of light on how it works and how
it differs from Nestybox's approach.

Rootless Docker works by creating a Linux user-namespace and running
the Docker daemon as well as the containers it creates within that
user-namespace.

By virtue of placing the Docker daemon inside a user-namespace, it no
longer runs as root on the host so unprivileged users on the host can
now be given access to the Docker daemon without fear of compromising
host security.

The caveat however is that removing root access from the Docker daemon
on the host results in important functional restrictions such as
cgroup resource control limitations, port exposure restrictions,
[among others][rootless-docker].

It's an interesting (and technically challenging) approach.

Without doing an extensive pros & cons comparison, we know that
Nestybox takes the approach of leaving the Docker daemon on the host
run with full privileges and running unprivileged Docker daemons
inside system containers. This way the Docker daemon on the host works
without functional restrictions, and each unprivileged user can get a
dedicated Docker daemon inside a well isolated system container.

More on rootless Docker here:

https://medium.com/@tonistiigi/experimenting-with-rootless-docker-416c9ad8c0d6

## TODO

* Evaluate security risks associated with mounting `/sys/fs/cgroup` as
  read-write inside container?

* Evaluate security risks with allowing mount syscall inside the
  sys-container; can unmounting / remounting be used by an attacker to
  bypass original mounts.

  - In particular: `/proc`, `/sys`, etc.

* Evaluate security risks with sysbox-fs `/proc` virtualization

  - Security on passthrough accesses

* Review Docker's default cgroup config; ideally it restricts / limits
  access to key machine resources to prevent attacks.

  - DoS attacks (forkbombs, PID exhaustion, etc.)

* Evaluate risk of exposing the following caps within a sys container:

  `CAP_SYS_MOUDULE` (lxc disables this one)
  `CAP_SYS_PTRACE` (though we use seccomp to block the ptrace() syscall); see section 8.3 on p74 of ncc whitepaper
  `CAP_SYS_RAWIO`  (in relation to devices we expose; do we expose `/dev/mem` or `/dev/kmem`, `/proc/kcore`, etc?)
  `CAP_MAC_ADMIN`  (lxc disables this)
  `CAP_MAC_OVERRIDE` (lxc disables this)
  `CAP_FOWNER`     (in relation to shared mounts or volumes)
  `CAP_DAC_READ_SEARCH` (allows calls to `open_by_handle_at()`, which opens several exploits; see shocker exploit)
  `CAP_SYS_BOOT`
  `CAP_MKNOD`
  `CAP_SYS_TIME`  (lxc disables this one)
  `CAP_SYS_LOG`   (in relation to exposure of kernel addresses via `/proc`; dmesg access; writing to kernel log)
  `CAP_NET_RAW`   (facilitates cross-container attacks; see ncc whitepaper, p55)

* Create an AppArmor profile for sys containers

  - Look at LXC's profile in `/etc/apparmor.d/abstractions/lxc/container-base`

* Research linux & docker "no new privileges" setting; and lack of
  interaction with AppArmor

* Research: is the kernel keyring namespaced? interaction with userns?

* sysbox build: enable apparmor in sysbox makefile

* sysbox: do we support apparmor in inner containers?

* sysbox: do we vet mounts to ensure none of them are over `/proc` or `/sys` ?

* Research: user-namespace vulnerabilities

* Research the "docker-bench-security" tool


## References

[1] https://www.nccgroup.trust/us/our-research/understanding-and-hardening-linux-containers/
