Sysboxd Usage Notes
====================

The customer docs for sysboxd contain the sysboxd user's guide.
See [here](https://github.com/nestybox/sysvisor-external/blob/master/docs/usage.md).

The following is additional usage info meant for Nestybox's internal
use only.

## Storage sharing between system containers

System containers use the Linux user-namespace for increased isolation
from the host and from other containers (i.e., each container has a
range of uids(gids) that map to a non-root user in the host).

A known issue with containers that use the user-namespace is that
sharing storage between them is not trivial because each container can
be potentially given an exclusive uid(gid) range on the host, and thus
may not have access to the shared storage (unless such storage has lax
permissions).

Sysboxd system containers support storage sharing between multiple
system containers, without lax permissions and in spite of the fact
that each system container may be assigned a different uid/gid range
on the host.

This uses uid(gid) shifting performed by the `shiftfs` module described
previously (see section "Docker without userns-remap" above).

Setting it up is simple:

First, create a shared directory owned by `root:root`:

```
sudo mkdir <path/to/shared/dir>
```

Then simply bind-mount the volume into the system container(s):

```
$ docker run --runtime=sysbox-runc \
    --rm -it --hostname syscont \
    --mount type=bind,source=<path/to/shared/dir>,target=</mount/path/inside/container>  \
    debian:latest
```

When the system container is launched this way, Sysboxd will notice
that bind mounted volume is owned by `root:root` and will mount
shiftfs on top of it, such that the container can have access to
it. Repeating this for multiple system containers will give all of
them access to the shared volume.

Note: for security reasons, ensure that *only* the root user has
search permissions to the shared directory. This prevents a scenario
where a corrupt/malicious system container writes an executable file
to this directory (as root) and makes it executable by any user
on the host, thereby granting regular users host privileges.
