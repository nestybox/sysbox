Sysbox's Systemd Support
=========================

This document outlines the set of requirements needed by systemd to
operate in container environments, and how these ones are being
satisfied by Sysbox's implementation. I'm also highlighting some of
the problems that we have encountered and their solutions.


# Requirements & Solutions

1) "/sys" to be mounted as read-only prior to systemd initialization.

    Solution: Already taken care of by sysbox-runc implementation.


2) "/proc" to be mounted prior to systemd initialization.

    Solution: Already takend care of by sysbox-runc implementation.


3) "/sys/fs/selinux" to be mounted prior to systemd initialization.

    Solution: Ignored for now.


4) "/proc/sys" and the entirety of "/sys" should ideally be mounted as
   read-only to avoid the possibility of containers altering the host
   kernel's configuration settings. Systemd and various other tools
   have been modified to detect whether these file-systems are
   read-only, and will behave accordingly.

    Solution: No changes here. Sysbox-runc mounts "/proc/sys" in
    read-write mode, whereas "/sys" is mounted as read-only. Deeper
    levels of "/sys" hierarchy are mounted as read-write, including
    "/sys/fs/cgroup".


5) "/dev/kmsg" to be mounted on a container-basis as tmpfs resource, and bind mount some
   suitable TTY to /dev/console.

    Solution: Systemd, and concretelly journald, demands the presence of "/dev/kmsg"
    for its regular I/O operations. This device is not exposed by runc during container
    creation. "Kind" folks have workaround'ed this issue by making a
    soft-link between "/dev/kmsg" and "/dev/console" in their (container)
    entrypoint scripts. However, this seems to be a bad idea as per
    systemd folks: "do not cross-link /dev/kmsg with /dev/console. They
    are different things, you cannot link them to each other".

    In sysbox's case we have opted for a simpler solution: we are exposing "/dev/kmsg"
    as a tmpfs resource.


6) Create device nodes for /dev/null, /dev/zero, /dev/full, /dev/random,
   /dev/urandom, /dev/tty, /dev/ptmx in /dev.

    Solution: No changes here, sysbox-runc is already creating most of these.


7) Make sure to set up the "devices" cgroup controller so that no other devices but
   the above ones may be created in the container.

    Solution: When using Docker to run sys containers, this restriction is placed by
    Docker in the system container's config.json file.


8) "/run" and "/run/lock" are expected.

    Solution: Sysbox-runc is adjusting incoming specs to add tmpfs mounts for these two
    resources.

9) "/tmp" is expected.

    Solution: Same as above: mount tmpfs over /tmp.


10) "/var/log/journal" is expected by journald to dump all received logs.

    Solution: I initially tried to mount tmpfs over /var/log/journal, but
    then i hit this issue when unmounting this resource during container shutdown:

    ```console
    [  OK  ] Stopped Network Name Resolution.
    [FAILED] Failed unmounting /var/log/journal.
    [  OK  ] Stopped Permit User Sessions.
    ```

    This one looks to be a known [issue](https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1788048)
    that hasn't been fully fixed in systemd yet. For the time being i have decided to avoid mounting
    this file, which doesn't seem to have any impact on journald functionality.

11) Systemd does not exit on SIGTERM. Systemd defines that shutdown signal as
    SIGRTMIN+3, however, "docker stop" sends the usual SIGTERM one.

    Solution: Enforce the proper shutdown signal in the sys-container Dockerfile --
    "STOPSIGNAL SIGRTMIN+3". We should explore the possibility of hardcoding this
    option in sysbox-runc to ease end-user's life.


12) Set "container" environment variable to allow systemd (and other
    code) to identify that it is executed within a container. With
    this in place the "ConditionVirtualization" setting in unit files
    will work properly. See
    [here](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
    for more details.

    Solution: For the time being we are expecting the user to be the
    one setting this env-var. As per the above doc, the best-match for
    our case seems to be "privilege-user" value, but "docker" seems to
    be working fine too. These are the values that we should encourage
    our users.

13) Systemd requires access to a 'configfs' and a 'debugfs'
    file-system for the proper operation of
    [systemd-modules-load.service](https://github.com/systemd/systemd/blob/99f57a4fea76ab86cf1bd64e44eabf7cea9a3d95/units/sys-kernel-config.mount). These
    file-systems are expected to be mounted in '/sys/kernel/config'
    and '/sys/kernel/debug' respectively.

    ```console
    [FAILED] Failed to mount Kernel Debug File System.
    ...
    [FAILED] Failed to mount Kernel Configuration File System.
    ...
    ```

    Solution: Even though LXD mounts these file-systems, they are limiting what can be seen/done
    through the utilization of [customized](https://github.com/lxc/lxd/blob/master/lxd/apparmor/apparmor.go)
    apparmor profiles, which makes sense given the sensitive nature of the information being exposed.

    We could mimic this apparmor-based approach, but it would require certain level
    of complexity that may not be strictly needed in this case. In fact, i have noticed
    that systemd doesn't really do much with these file-systems, and there's no
    need to have a full-blown hierarchy of files/dirs under them. Thereby,
    the solution to this is issue is to expose dummy (tmpfs-based) resources:

    ```console
    |-/sys/kernel/config      tmpfs     tmpfs    rw,nosuid,nodev,noexec,relatime,uid=165536,gid=165536
    |-/sys/kernel/debug       tmpfs     tmpfs    rw,nosuid,nodev,noexec,relatime,uid=165536,gid=165536
    ```

14) By default systemd enables 'getty.service' to enforce
    authentication-based access to the system. Users accessing
    container's console (i.e. 'docker run') will encounter a 'login'
    prompt once the container is fully initialized. The problem for us
    here is: which default user do we provide, and more importantly,
    how do we create it in a programmatic maneer?

    Solution: The user himself will need to create this default user through the utilization of this (or similar) Dockerfile instruction:

    ```console
    ...
    # Create default 'admin/admin' user
    useradd --create-home --shell /bin/bash admin && echo "admin:admin" | chpasswd && adduser admin sudo &&
    ...
    ```

15) Dbus unable to initialize.

    Let's start with some background info first. In a nutshell, D-Bus is a message bus system, a simple way for
    applications to talk to one another (yet another ipc library). There are [multiple](https://www.freedesktop.org/wiki/Software/DbusProjects/)
    applications relying on the services it offers.

    ```console
    root@testing-1:~# hostnamectl
    Failed to create bus connection: No such file or directory
    ```

    Solution: Obvious this time. Systemd is properly configured (by default) to launch dbus service, as long as this one is installed (dbus package). Adjust systemd Dockerfile to incorporate this dependency.

    ```console
    admin@testing-1:~$ hostnamectl
     Static hostname: testing-1
           Icon name: computer-container
             Chassis: container
          Machine ID: 7132027b7c54475fbf8e5f263bc4756b
             Boot ID: 5b758ed7877f45bc85e5e5b8ecf48370
      Virtualization: container-other
    Operating System: Ubuntu 18.04.3 LTS
              Kernel: Linux 5.0.0-29-generic
        Architecture: x86-64
    ```

16) Systemd errors generated due to missing '/etc/default/locale' file. This file is typically generated by default as part of the "locales" debian package installation.

    ```console
    Oct 21 04:07:21 testing-1 sudo[1488]:    admin : TTY=console ; PWD=/home/admin ; USER=root;COMMAND=/usr/bin/apt-get install locales                      │                {
    Oct 21 04:07:21 testing-1 sudo[1488]: pam_env(sudo:session): Unable to open env file: /etc/default/locale: No such file or directory
    ...
    ```

    Solution: Simply add "locales" package to the Dockerfile creating the systemd container.



Note: I'm deliveratily obviating the requirements to allow the
integration of the container's systemd with the host's one, so that
system-containers can be potentially managed from the host. I'm also
ignoring the container-cgroup settings associated to systemd
demands. TBD.


# References

https://www.freedesktop.org/wiki/Software/systemd/ContainerInterface/
https://developers.redhat.com/blog/2019/04/24/how-to-run-systemd-in-a-container/
https://developers.redhat.com/blog/2016/09/13/running-systemd-in-a-non-privileged-container/
https://developers.redhat.com/blog/2014/05/05/running-systemd-within-docker-container/
