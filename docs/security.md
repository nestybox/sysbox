Sysbox Security Guide (Internal)
================================

The customer docs for sysbox info on sysbox's security.
See [here](https://github.com/nestybox/sysbox-staging/blob/master/docs/security.md).

The following is additional design information meant for Nestybox's
internal use only.

### "Rootless Docker" vs. System Containers

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
