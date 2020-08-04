Nestybox System Container Dockerfiles
=====================================

This directory contains the Dockerfiles for system container images
uploaded to the Nestybox public repos on DockerHub.

The Dockerfiles and associated images are meant to be used as examples.

Feel free to copy them and modify them to your needs, or source them
from within your Dockerfiles.

# Pulling a Nestybox system container image from DockerHub

For example, to run the system container image that contains Ubuntu Disco + Docker, simply type:

```console
$ docker run --runtime=sysbox-runc -it nestybox/ubuntu-disco-docker:latest
```

# Customizing the system container to your needs

Two approaches: either source the Nestybox image from within your own
Dockerfile, or copy the Nestybox Dockerfile and modify it.

The former approach makes sense if you wish to leverage the entire image.

The latter approach makes sense if there is some instruction within the
Nestybox Dockerfile that you wish to change.

## Sourcing the Nestybox Image

Simply add this at the beginning of your Dockerfile

```console
FROM nestybox/ubuntu-disco-docker:latest
```

Then add your instructions to the Dockerfile.

Then build the image and tag it:

```console
$ docker build .
$ docker tag <image-tag> my-custom-syscont:latest
```

And run it with:

```console
$ docker run --runtime=sysbox-runc -it my-custom-syscont:latest
```

You can then push the image to your own container image repo for later re-use.

## Copy the Dockerfile, modify it, and build a new image

First, copy the Nestybox Dockerfile to some directory, `cd` to that directory, and modify it per your needs.

Then build the image and tag it:

```console
$ docker build .
$ docker tag <image-tag> my-custom-syscont:latest
```

And run it with:

```console
$ docker run --runtime=sysbox-runc -it my-custom-syscont:latest
```

You can then push the image to your own container image repo for later re-use.
