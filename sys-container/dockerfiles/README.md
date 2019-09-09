Dockerfiles for system container images
=======================================

The Dockerfiles in the sub-directories correspond to system container
images meant for internal use within Nestybox.

**Note**: when pushing these to the Nestybox DockerHub repos, make sure they are pushed to private repos.

The Dockerfiles for system container images meant for our customers
are stored in the sysbox external repo. The resulting images are
pushed into Nestybox's public repos on DockerHub.


## To build an image:

Go to the directory where the Dockerfile is and run:

```
$ docker build .
```

## Image tagging

Tag the sys container image with a short name that describes its
contents. E.g.,:

```
$ docker tag <image-tag> nestybox/ubuntu-disco-docker-dbg:latest
```

## Image push

To push the sys container image to the Nestybox repo on DockerHub:

```
$ docker login
$ docker push nestybox/ubuntu-disco-docker-dbg:latest
```

**Note**: images intended for internal use must be stored in a private Nestybox repo.

## Image pull

To pull an image from the private repo:

```
$ docker pull nestybox/ubuntu-disco-docker-dbg:latest
```
