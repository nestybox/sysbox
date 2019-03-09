# Dockerfiles for system container images

## To build an image:

Go to the directory where the Dockerfile is and run:

```
$ docker build .
```

## Image tagging

Tag the image with "nestybox/sys-container:<image-description>"

```
$ docker tag nestybox/sys-container:debian-plus-docker
```

## Image push / pull

To push an image to the nestybox repo:

```
$ docker login nestybox
$ docker push nestybox/sys-container:debian-plus-docker
```

To pull an image from the repo:

```
$ docker pull nestybox/sys-container:debian-plus-docker
```
