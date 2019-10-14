Sysbox's Systemd Solution
=========================

This document outlines the set of requirements needed by systemd to operate
in container environments, and how these ones are being satisfied by Sysbox's
implementation.


# Requirements & Solutions

1) "/sys" to be mounted as read-only prior to systemd initialization.

    Solution: Already taken care of by default sysbox-runc implementation.


2) "/proc" to be mounted prior to systemd initialization.

    Solution: Already takend care of by default sysbox-runc implementation.


3) "/sys/fs/selinux" to be mounted prior to systemd initialization.

    Solution: Ignored for now.


4) "/proc/sys" and the entirety of "/sys" should ideally be mounted as read-only
to avoid the possibility of containers altering the host kernel's configuration
settings. Systemd and various other tools have been modified to detect
whether these file-systems are read-only, and will behave accordingly.

    Solution: No changes here. Sysbox-runc mounts "/proc/sys" in read-write mode,
whereas "/sys" is mounted as read-only. Deeper levels of "/sys" hierarchy are
mounted as read-write, including "/sys/fs/cgroup".


5) "/dev" to be mounted on a container-basis as tmpfs resource, and bind mount some
suitable TTY to /dev/console.

    Solution: Systemd, and concretelly journald, demands the presence of "/dev/kmsg"
for its regular I/O operations. This device is not exposed by runc during container
creation. "Kind" folks have workaround'ed this issue by making a soft-link between
"/dev/kmsg" and "/dev/console" in their (container) entrypoint scripts. However,
this seems to be a bad idea as per systemd folks: "do not cross-link /dev/kmsg with
/dev/console. They are different things, you cannot link them to each other".

    In sysbox's case we have opted for a simpler solution: we are exposing "/dev/kmsg"
as a tmpfs resource.


6) Create device nodes for /dev/null, /dev/zero, /dev/full, /dev/random,
/dev/urandom, /dev/tty, /dev/ptmx in /dev.

    Solution: No changes here, sysbox-runc is already creating most of these.


7) Make sure to set up the "devices" cgroup controller so that no other devices but
the above ones may be created in the container.

    Solution: Ignored for now.


8) "/run" and "/run/lock" are expected.

    Solution: Sysbox-runc is adjusting incoming specs to add tmpfs mounts for these two
resources.

9) "/tmp" is expected.

    Solution: Same as above: mount tmpfs over /tmp.


10) "/var/log/journal" is expected by journald to dump all received logs.

    Solution: Same as above: mount tmpfs over /var/log/journal.


11) Systemd does not exit on SIGTERM. Systemd defines that shutdown signal as
SIGRTMIN+3, however, "docker stop" sends the usual SIGTERM one.

    Solution: Enforce the proper shutdown signal in the sys-container Dockerfile --
"STOPSIGNAL SIGRTMIN+3". We should explore the possibility of hardcoding this
option in sysbox-runc to ease end-user's life.


12) Set "container" environment variable to allow systemd (and other code) to identify
  that it is executed within a container. With this in place the
  "ConditionVirtualization" setting in unit files will work properly. See
  [here](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
  for more details.

    Solution: For the time being we are expecting the user to be the one setting this
env-var. As per the above doc, the best-match for our case seems to be
"privilege-user" value, but "docker" seems to be working fine too. These are the
values that we should encourage our users.


Note: I'm deliveratily obviating the requirements that allows the integration of
the container's systemd with the host's one. I'm also ignoring the container-cgroup
settings associated to systemd demands. TBD.


# References

[1] https://www.freedesktop.org/wiki/Software/systemd/ContainerInterface/