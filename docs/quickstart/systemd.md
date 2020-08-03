# Sysbox Quick Start Guide: Systemd-in-Docker

This sections shows examples for deploying system containers that include
systemd inside.

The [User Guide](../user-guide/systemd.md) describes this functionality in
deeper detail.

## Deploy a System Container with Systemd inside

Deploying systemd inside a system container is useful when you plan to
run multiple services inside the system container, or when you want to
use it as a virtual host environment.

We will use a system container image that has Ubuntu Bionic + Systemd
inside. It's called `nestybox/ubuntu-bionic-systemd` and it's in the
Nestybox DockerHub repo. The Dockerfile is [here](../../dockerfiles/ubuntu-bionic-systemd/Dockerfile).

1) Start the system container:

```console
$ docker run --runtime=sysbox-runc --rm -it --hostname=syscont nestybox/ubuntu-bionic-systemd

systemd 237 running in system mode. (+PAM +AUDIT +SELINUX +IMA +APPARMOR +SMACK +SYSVINIT +UTMP +LIBCRYPTSETUP +GCRYPT +GNUTLS +ACL +XZ +LZ4 +SECCOMP +BLKID +ELFUTILS +KMOD -IDN2 +IDN -PCRE2 default-hierarchy=hybrid)
Detected virtualization container-other.
Detected architecture x86-64.

Welcome to Ubuntu 18.04.3 LTS!

Set hostname to <syscont>.
Failed to read AF_UNIX datagram queue length, ignoring: No such file or directory
Failed to install release agent, ignoring: No such file or directory
File /lib/systemd/system/systemd-journald.service:35 configures an IP firewall (IPAddressDeny=any), but the local system does not support BPF/cgroup based firewalling.
Proceeding WITHOUT firewalling in effect! (This warning is only shown for the first loaded unit using IP firewalling.)
[  OK  ] Reached target Swap.

...

[  OK  ] Reached target Login Prompts.
[  OK  ] Started Login Service.
[  OK  ] Reached target Multi-User System.
[  OK  ] Reached target Graphical Interface.
         Starting Update UTMP about System Runlevel Changes...
[  OK  ] Started Update UTMP about System Runlevel Changes.

Ubuntu 18.04.3 LTS syscont console

syscont login:
```

2) Login to the container:

In the system container image we are using, we've configured the
default console login and password to be `admin/admin` (you can always
change this in the image's Dockerfile).

```console
syscont login: admin
Password:
Welcome to Ubuntu 18.04.3 LTS (GNU/Linux 5.0.0-31-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage
This system has been minimized by removing packages and content that are
not required on a system that users do not log into.

To restore this content, you can run the 'unminimize' command.

The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

admin@syscont:~$
```

3) Verify systemd is running correctly:

```console
admin@syscont:~$ ps -fu root
UID        PID  PPID  C STIME TTY          TIME CMD
root         1     0  0 23:41 ?        00:00:00 /sbin/init
root       252     1  0 23:41 ?        00:00:00 /lib/systemd/systemd-journald
root       685     1  0 23:41 ?        00:00:00 /lib/systemd/systemd-logind
root       725     1  0 23:41 pts/0    00:00:00 /bin/login -p --

admin@syscont:~$ systemctl
UNIT                                     LOAD   ACTIVE SUB       DESCRIPTION
-.mount                                  loaded active mounted   Root Mount
dev-full.mount                           loaded active mounted   /dev/full
dev-kmsg.mount                           loaded active mounted   /dev/kmsg
dev-mqueue.mount                         loaded active mounted   POSIX Message Queue File System
dev-null.mount                           loaded active mounted   /dev/null
dev-random.mount                         loaded active mounted   /dev/random

...

timers.target                            loaded active active    Timers
apt-daily-upgrade.timer                  loaded active waiting   Daily apt upgrade and clean activities
apt-daily.timer                          loaded active waiting   Daily apt download activities
motd-news.timer                          loaded active waiting   Message of the Day
systemd-tmpfiles-clean.timer             loaded active waiting   Daily Cleanup of Temporary Directories

LOAD   = Reflects whether the unit definition was properly loaded.
ACTIVE = The high-level unit activation state, i.e. generalization of SUB.
SUB    = The low-level unit activation state, values depend on unit type.

74 loaded units listed. Pass --all to see loaded but inactive units, too.
To show all installed unit files use 'systemctl list-unit-files'.
```

4) To exit the system container, you can break from it (by pressing `ctrl-p
   ctrl-q`). You can then stop the system container by using the `docker stop`
   command from the host.

5) Alternatively, from another shell type:

```console
$ docker ps
CONTAINER ID        IMAGE                            COMMAND             CREATED             STATUS              PORTS               NAMES
3236bcdd2313        nestybox/ubuntu-bionic-systemd   "/sbin/init"        23 minutes ago      Up 23 minutes                           zen_blackburn

$ docker stop zen_blackburn
zen_blackburn
```

And back in the shell where the system container is running, you'll
see systemd shutting down all services in the system container:

```console
[  OK  ] Removed slice system-getty.slice.
[  OK  ] Stopped target Host and Network Name Lookups.
         Stopping Network Name Resolution...
[  OK  ] Stopped target Graphical Interface.
[  OK  ] Stopped target Multi-User System.

...

[  OK  ] Reached target Shutdown.
[  OK  ] Reached target Final Step.
         Starting Halt...
```
