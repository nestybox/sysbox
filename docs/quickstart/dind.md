# Sysbox Quick Start Guide: Docker-in-Docker

This section shows examples for running Docker inside system containers.

The [User Guide](../user-guide/dind.md) describes this functionality in
deeper detail.

## Contents

-   [Deploy a System Container with Docker inside](#deploy-a-system-container-with-docker-inside)
-   [Deploy a System Container with Systemd, sshd, and Docker inside](#deploy-a-system-container-with-systemd-sshd-and-docker-inside)
-   [Deploy a System Container with Supervisord and Docker inside](#deploy-a-system-container-with-supervisord-and-docker-inside)
-   [Persistence of Inner Container Images using Docker Volumes](#persistence-of-inner-container-images-using-docker-volumes)
-   [Persistence of Inner Container Images using Bind Mounts](#persistence-of-inner-container-images-using-bind-mounts)

## Deploy a System Container with Docker inside

We will use a system container image that has Alpine + Docker inside. It's called
`nestybox/alpine-docker` and it's in the [Nestybox DockerHub repo](https://hub.docker.com/u/nestybox). The
Dockerfile is [here](https://github.com/nestybox/dockerfiles/blob/master/alpine-docker/Dockerfile).

1) Start the system container:

```console
$ docker run --runtime=sysbox-runc -it --hostname=syscont nestybox/alpine-docker:latest
```

2) Start the inner Docker:

```console
/ # which docker
/usr/bin/docker

/ # dockerd > /var/log/dockerd.log 2>&1 &
```

3) Verify Docker started correctly:

```console
/ # tail /var/log/dockerd.log
time="2019-10-23T20:48:51.960846074Z" level=warning msg="Your kernel does not support cgroup rt runtime"
time="2019-10-23T20:48:51.960860148Z" level=warning msg="Your kernel does not support cgroup blkio weight"
time="2019-10-23T20:48:51.960872060Z" level=warning msg="Your kernel does not support cgroup blkio weight_device"
time="2019-10-23T20:48:52.146157113Z" level=info msg="Loading containers: start."
time="2019-10-23T20:48:52.235036055Z" level=info msg="Default bridge (docker0) is assigned with an IP address 172.18.0.0/16. Daemon option --bip can be used to set a preferred IP address"
time="2019-10-23T20:48:52.324207525Z" level=info msg="Loading containers: done."
time="2019-10-23T20:48:52.476235437Z" level=warning msg="Not using native diff for overlay2, this may cause degraded performance for building images: failed to set opaque flag on middle layer: operation not permitted" storage-driver=overlay2
time="2019-10-23T20:48:52.476418516Z" level=info msg="Docker daemon" commit=0dd43dd87fd530113bf44c9bba9ad8b20ce4637f graphdriver(s)=overlay2 version=18.09.8-ce
time="2019-10-23T20:48:52.476533826Z" level=info msg="Daemon has completed initialization"
time="2019-10-23T20:48:52.489489309Z" level=info msg="API listen on /var/run/docker.sock"

/ # docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
```

4) Start an inner container:

```console
/ # docker run -it busybox
Unable to find image 'busybox:latest' locally
latest: Pulling from library/busybox
7c9d20b9b6cd: Pull complete
Digest: sha256:fe301db49df08c384001ed752dff6d52b4305a73a7f608f21528048e8a08b51e
Status: Downloaded newer image for busybox:latest
/ #
```

As shown, Docker runs normally inside the secure system container and we
can deploy an inner container (busybox) without problem.

The Sysbox runtime allows you to do this easily and securely (no complex
Docker run commands, no unsecure Docker privileged containers!).

## Deploy a System Container with Systemd, sshd, and Docker inside

In the prior example we did not have Systemd (or any other process manager) in
the container, so we had to manually start Docker inside the container.

This example improves on this by deploying a system container that has both
Systemd and Docker inside.

We've also added an SSH daemon in into the system container image, so that you
can login remotely into it, just as you would on a physical host or VM.

We will use a system container image called `nestybox/ubuntu-bionic-systemd-docker:latest` which is in
[Nestybox DockerHub repo](https://hub.docker.com/u/nestybox). The Dockerfile is
[here](https://github.com/nestybox/dockerfiles/blob/master/ubuntu-bionic-systemd-docker/Dockerfile).

1) Start the system container:

```console
$ docker run --runtime=sysbox-runc -it --rm -P --hostname=syscont nestybox/ubuntu-bionic-systemd-docker:latest
systemd 237 running in system mode. (+PAM +AUDIT +SELINUX +IMA +APPARMOR +SMACK +SYSVINIT +UTMP +LIBCRYPTSETUP +GCRYPT +GNUTLS +ACL +XZ +LZ4 +SECCOMP +BLKID +ELFUTILS +KMOD -IDN2 +IDN -PCRE2 default-hierarchy=hybrid)
Detected virtualization container-other.
Detected architecture x86-64.

Welcome to Ubuntu 18.04.3 LTS!

Set hostname to <syscont>.

...

[  OK  ] Started Docker Application Container Engine.
[  OK  ] Reached target Multi-User System.
[  OK  ] Reached target Graphical Interface.
         Starting Update UTMP about System Runlevel Changes...
[  OK  ] Started Update UTMP about System Runlevel Changes.

Ubuntu 18.04.3 LTS syscont console

syscont login:
```

2) Login to the container:

In the system container image we are using, we've configured the
default console login and password to be `admin/admin`. You can always
change this in the image's Dockerfile.

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

3) Verify that Systemd has started Docker:

```console
admin@syscont:~$ systemctl status docker.service
● docker.service - Docker Application Container Engine
   Loaded: loaded (/lib/systemd/system/docker.service; enabled; vendor preset: enabled)
   Active: active (running) since Thu 2019-10-24 00:33:09 UTC; 8s ago
     Docs: https://docs.docker.com
 Main PID: 715 (dockerd)
    Tasks: 12
   CGroup: /system.slice/docker.service
           └─715 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock

admin@syscont:~$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
```

4) Start an inner container:

```console
admin@syscont:~$ docker run -it busybox
Unable to find image 'busybox:latest' locally
latest: Pulling from library/busybox
7c9d20b9b6cd: Pull complete
Digest: sha256:fe301db49df08c384001ed752dff6d52b4305a73a7f608f21528048e8a08b51e
Status: Downloaded newer image for busybox:latest
/ #
```

Good, it works!

5) Now let's ssh into the system container.

In order to do this, we need the host's IP address as well as the host port that
is mapped to the system container's sshd port.

In my case, the host's IP address is 10.0.0.230. The ssh daemon is
listening on port 22 in the system container, which is mapped to some
arbitrary port on the host machine.

Let's find out what that arbitrary port is. From the host, type:

```console
$ docker ps
CONTAINER ID        IMAGE                                          COMMAND             CREATED             STATUS              PORTS                   NAMES
e22773df703e        nestybox/ubuntu-bionic-systemd-docker:latest   "/sbin/init"        16 seconds ago      Up 15 seconds       0.0.0.0:32770->22/tcp   sad_kepler
```

6) From a different machine, ssh into the system container:

```console
$ ssh admin@10.0.0.230 -p 32770

The authenticity of host '[10.0.0.230]:32770 ([10.0.0.230]:32770)' can't be established.
ECDSA key fingerprint is SHA256:VNHrxvsHp4aJYH/DQjvBMdeoF0HBP2yKtWc815WtnnI.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '[10.0.0.230]:32770' (ECDSA) to the list of known hosts.
admin@10.0.0.230's password:
Last login: Thu Oct 24 03:47:39 2019
To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

admin@syscont:~$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
```

Great, the ssh worked without problem.

This is cool because you now have a system container that is acting
like a virtual host with Systemd and sshd. Plus it has Docker inside
so you can deploy application containers in complete isolation from
the underlying host.

## Deploy a System Container with Supervisord and Docker inside

Systemd is great but may be too heavy-weight for some use cases.

A good alternative is to use supervisord as a light weight process
manager inside a system container.

We will use a system container image called `nestybox/alpine-supervisord-docker:latest`.
Nestybox DockerHub public repo. The Dockerfile, supervisord.conf, and docker-entrypoint.sh files
can be found [here](https://github.com/nestybox/dockerfiles/tree/master/alpine-supervisord-docker).

1) Start the system container:

```console
$ docker run --runtime=sysbox-runc -d --rm -P --hostname=syscont nestybox/alpine-supervisord-docker:latest
f3b90976ad0550fc8142568d988c8fa65c54864d04c1637e88323a32f87cf3af
```

2) Verify that supervisord started all services inside the system container.

From the host, type:

```console
$ docker ps
CONTAINER ID        IMAGE                                       COMMAND                  CREATED             STATUS              PORTS                   NAMES
f3b90976ad05        nestybox/alpine-supervisord-docker:latest   "/usr/bin/docker-ent…"   2 seconds ago       Up 1 second         0.0.0.0:32776->22/tcp   sleepy_shamir

$ docker exec -it sleepy_shamir ps
PID   USER     TIME  COMMAND
    1 root      0:00 {supervisord} /usr/bin/python2 /usr/bin/supervisord -n
    7 root      0:00 /usr/sbin/sshd -D
    8 root      0:02 /usr/bin/dockerd
   36 root      0:03 containerd --config /var/run/docker/containerd/containerd.
  980 root      0:00 ps
```

As shown, supervisord is running as the init process and has spawned
sshd and dockerd. Cool.

3) Now let's ssh into the system container.

In this example the host machine is at IP 10.0.0.230, and the system container's
ssh port is mapped to host port 32776 as indicated by the `docker ps` output
above. The login is `root:root` as configured in the image's Dockerfile.

```console
$ ssh root@10.0.0.230 -p 32776
The authenticity of host '[10.0.0.230]:32776 ([10.0.0.230]:32776)' can't be established.
RSA key fingerprint is SHA256:/p++Ju2yo5SF1obEV4TeI+Fq6Q2DBErdboO287aSNp0.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '[10.0.0.230]:32776' (RSA) to the list of known hosts.
root@10.0.0.230's password:
Welcome to Alpine!

The Alpine Wiki contains a large amount of how-to guides and general
information about administrating Alpine systems.
See <http://wiki.alpinelinux.org/>.

You can setup the system with the command: setup-alpine

You may change this message by editing /etc/motd.
syscont:~#
```

4) Run a Docker container inside the system container:

```console
syscont:~# docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
syscont:~# docker run -it busybox
Unable to find image 'busybox:latest' locally
latest: Pulling from library/busybox
7c9d20b9b6cd: Pull complete
Digest: sha256:fe301db49df08c384001ed752dff6d52b4305a73a7f608f21528048e8a08b51e
Status: Downloaded newer image for busybox:latest
/ # syscont:~#
```

## Persistence of Inner Container Images using Docker Volumes

The Docker instance running inside a system container stores its
images in a cache located in the `/var/lib/docker` directory
inside the container.

When the system container is removed (i.e., via `docker rm`), the contents of
that directory will also be removed. In other words, inner Docker's image cache
is destroyed when the associated system container is removed.

It's possible to override this behavior by mounting host storage into
the system container's `/var/lib/docker` in order to persist the
inner Docker's image cache across system container life-cycles.

In fact, not only do inner Docker images persist; inner containers will also
persist (thought they will need to be restarted).

Here is an example:

1) Create a Docker volume on the host to serve as the persistent image cache for
   the Docker daemon inside the system container.

```console
$ docker volume create myvol
myvol

$ docker volume list
DRIVER              VOLUME NAME
local               myvol
```

2) Launch the system container and mount the volume into the system
   container's `/var/lib/docker` directory.

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname syscont --mount source=myvol,target=/var/lib/docker nestybox/alpine-docker
/ #
```

3) Start Docker inside the system container:

```console
/ # dockerd > /var/log/dockerd.log 2>&1 &
```

4) Pull an inner container image (e.g. busybox):

```console
/ # docker pull busybox
Using default tag: latest
latest: Pulling from library/busybox
7c9d20b9b6cd: Pull complete
Digest: sha256:fe301db49df08c384001ed752dff6d52b4305a73a7f608f21528048e8a08b51e
Status: Downloaded newer image for busybox:latest

/ # docker image ls
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
busybox             latest              19485c79a9bb        7 weeks ago         1.22MB
```

5) Create an inner container:

```console
/ # docker run -d --name inner-container busybox tail -f /dev/null
56ccb4bb33280f3f670956f6f06afde08e8219eb56c9d79a8b0e5d925ecee96d

/ # docker ps
CONTAINER ID        IMAGE               COMMAND               CREATED             STATUS              PORTS               NAMES
56ccb4bb3328        busybox             "tail -f /dev/null"   4 seconds ago       Up 2 seconds                            inner-container
```

6) Exit the system container.

This causes the inner container to be automatically stopped.

The contents of the system container's `/var/lib/docker` will persist since they
are stored in volume `myvol`.

7) Start a new system container and mount `myvol` into it:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname syscont --mount source=myvol,target=/var/lib/docker nestybox/alpine-docker
```

8) Start Docker inside:

```console
/ # dockerd > /var/log/dockerd.log 2>&1 &
```

9) Verify that the inner Docker images persisted:

```console
/ # docker image ls
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
busybox             latest              19485c79a9bb        7 weeks ago         1.22MB
```

There they are!

10) Verify that the inner Docker container persisted:

```console
/ # docker ps -a

CONTAINER ID        IMAGE               COMMAND               CREATED             STATUS                       PORTS               NAMES
56ccb4bb3328        busybox             "tail -f /dev/null"   32 seconds ago      Exited (255) 3 seconds ago                       inner-container

/ # docker start inner-container
inner-container
/ # docker ps -a
CONTAINER ID        IMAGE               COMMAND               CREATED             STATUS              PORTS               NAMES
56ccb4bb3328        busybox             "tail -f /dev/null"   42 seconds ago      Up 1 second                             inner-container
```

There is it is!

As shown, the inner container images and even inner containers persisted across
the life-cycle of the system container.

This is cool because it means that a system container can leverage an existing
Docker image cache stored somewhere on the host, thus avoiding having to pull
those inner Docker images from the network each time a new system container is
started.

There are a couple of important caveats to keep in mind:

-   A Docker volume mounted into the system container's `/var/lib/docker` must
    only be mounted on a **single system container at any given time**.

    -   This is a restriction imposed by the Docker daemon, which does not allow
        its image cache to be shared concurrently among multiple daemon
        instances.

    -   Sysbox will check for violations of this rule and report an
        appropriate error during system container creation.

-   A Docker volume mounted into the system container's `/var/lib/docker`
    will **inherit** any files present in that same directory as part of the system
    container's image. Such files would be present when using system containers
    that have preloaded inner container images.

    -   In other words, if the system container comes preloaded with inner images,
        those will be automatically transferred to the Docker volume when the
        system container starts, and will persist across the system container
        life-cycle.

    -   Note that this behavior is different than when bind-mounting host
        directories into the system container `/var/lib/docker` (see next
        section).

## Persistence of Inner Container Images using Bind Mounts

This section is similar to the prior one, but uses bind mounts instead
of Docker volumes when launching the system container.

The steps to do this are the following:

1) Create a directory on the host to serve as the persistent image cache for
   the Docker daemon inside the system container.

   As described in the [Sysbox User Guide](../user-guide/storage.md#system-container-bind-mount-requirements)
   the directory should be owned by a user in the range [0:65536] and
   will show up with those same user-IDs within the system
   container. In this example we choose user-ID 0 (root) so that the
   Docker instance inside the system container will see it's
   `/var/lib/docker` directory owned by `root:root` inside the system
   container.

   For extra security, we will also set the permission to 0700 as
   recommended in the Sysbox Users Guide.

```console
$ sudo mkdir /home/someuser/image-cache
$ sudo chmod 700 /home/someuser/image-cache
```

2) Launch the system container and bind-mount the newly created
   directory into the system container's `/var/lib/docker` directory.

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname syscont --mount type=bind,source=/home/someuser/image-cache,target=/var/lib/docker nestybox/alpine-docker
/ #
```

3) Start Docker inside the system container and pull an image (e.g., busybox):

```console
/ # dockerd > /var/log/dockerd.log 2>&1 &

/ # docker pull busybox
Using default tag: latest
latest: Pulling from library/busybox
7c9d20b9b6cd: Pull complete
Digest: sha256:fe301db49df08c384001ed752dff6d52b4305a73a7f608f21528048e8a08b51e
Status: Downloaded newer image for busybox:latest

/ # docker image ls
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
busybox             latest              19485c79a9bb        7 weeks ago         1.22MB
```

4) Exit the system container.

5) Start a new system container and bind-mount the `my-image-cache`
   directory as before:

```console
$ docker run --runtime=sysbox-runc -it --rm --hostname syscont --mount type=bind,source=/home/someuser/image-cache,target=/var/lib/docker nestybox/alpine-docker
```

6) Start Docker inside the system container and verify that it sees
   the images from the bind-mounted cache:

```console
/ # dockerd > /var/log/dockerd.log 2>&1 &
/ # docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES

/ # docker image ls
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
busybox             latest              19485c79a9bb        7 weeks ago         1.22MB
```

There are a couple of caveats to keep in mind here:

-   A host directory bind-mounted into the system container's `/var/lib/docker` must
    only be mounted on a **single system container at any given time**. This is
    a restriction imposed by the inner Docker daemon, which does not allow its image
    cache to be shared concurrently among multiple daemon instances. Sysbox will
    check for violations of this rule and report an appropriate error during
    system container creation.

-   A host directory bind-mounted into the system container's `/var/lib/docker`
    will "mask" any files present in that same directory as part of the system
    container's image. Such files would be present when using system containers
    that have preloaded inner container images.

    -   This behavior differs from when Docker volume mounts are mounted into
        the system container's `/var/lib/docker` (see prior section).
