#!/usr/bin/env bats

#
# Basic tests for running Docker builds inside Sysbox containers.
#

load ../helpers/crictl
load ../helpers/userns
load ../helpers/k8s
load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

# Test image to generate during testing.
image="test_nginx"

# This dockerfile will be passed into the system containers via a bind-mount.
file="/root/Dockerfile"

# Test docker build inside a sysbox container.
@test "docker build inside sysbox container" {

  cat << EOF > ${file}
FROM ${CTR_IMG_REPO}/alpine
MAINTAINER Nestybox
RUN apk update && apk add nginx
COPY . /root
EXPOSE 8080
CMD ["echo","Image created"]
EOF

  # Retry: a transient registry pull failure here (e.g. connection reset)
  # would otherwise leave $syscont empty and fail confusingly downstream in
  # wait_for_inner_dockerd. Can't use retry_run since docker_run() calls
  # bats' run() internally via the docker() wrapper, and nesting run() calls
  # corrupts $output/$status.
  for attempt in 1 2 3; do
    syscont=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile ${CTR_IMG_REPO}/ubuntu-jammy-systemd-docker:latest tail -f /dev/null)
    [ -n "$syscont" ] && break
    sleep 3
  done
  [ -n "$syscont" ]

  wait_for_inner_dockerd $syscont

  docker exec $syscont sh -c "cd /mnt && docker buildx build -t $image ."
  [ "$status" -eq 0 ]

  docker exec $syscont sh -c "docker run --rm $image"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Image created" ]]

  docker exec $syscont sh -c "docker rmi $image"
  [ "$status" -eq 0 ]

  docker_stop $syscont

  rm $file
}

# Tests docker build using the docker-container driver and sysbox runtime (i.e.,
# the build happens inside a sysbox container).
@test "docker build with sysbox-backed docker-container driver" {

  docker buildx version
  if [ "$status" -ne 0 ]; then
	  skip "docker buildx command not supported; update to latest docker version when available"
  fi

  cat << EOF > ${file}
FROM ${CTR_IMG_REPO}/alpine
MAINTAINER Nestybox
RUN apk update && apk add nginx
COPY . /root
EXPOSE 8080
CMD ["echo","Image created"]
EOF

  docker buildx create --name l1-buildkit --driver docker-container --use
  [ "$status" -eq 0 ]

  docker buildx ls
  [ "$status" -eq 0 ]

  docker buildx inspect --bootstrap
  [ "$status" -eq 0 ]

  docker buildx build --load -t $image -f $file /mnt
  [ "$status" -eq 0 ]

  docker run --rm $image
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Image created" ]]

  docker rmi $image
  [ "$status" -eq 0 ]

  docker buildx prune -f
  [ "$status" -eq 0 ]

  docker buildx rm
  [ "$status" -eq 0 ]

  rm $file
}

# Test basic buildkit features when this one is launched within a sysbox container
# (i.e., buildkit runs at L2 level).
@test "test docker container driver inside a sysbox container" {

  docker buildx version
  if [ "$status" -ne 0 ]; then
	  skip "docker buildx command not supported; update to latest docker version when available"
  fi

  cat << EOF > ${file}
FROM ${CTR_IMG_REPO}/alpine
MAINTAINER Nestybox
RUN apk update && apk add nginx
COPY . /root
EXPOSE 8080
CMD ["echo","Image created"]
EOF

  local syscont=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile ${CTR_IMG_REPO}/ubuntu-jammy-systemd-docker:latest tail -f /dev/null)

  wait_for_inner_dockerd $syscont

  # Obtain sys container's ip address.
  docker exec $syscont bash -c "ip address show dev eth0 | grep -w inet | cut -d\"/\" -f1 | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  local syscont_ip=${output}

  # Configure container's key-based ssh access.
  docker_ssh_access $syscont
  [ "$status" -eq 0 ]

  # Create a remote buildx node within a sys container.
  docker buildx create --name l2-buildkit ssh://${syscont_ip}:22 --driver docker-container --use
  [ "$status" -eq 0 ]

  docker buildx ls
  [ "$status" -eq 0 ]

  docker buildx inspect --bootstrap
  [ "$status" -eq 0 ]

  docker buildx build --load -t $image -f $file /mnt
  [ "$status" -eq 0 ]

  docker run --rm $image
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Image created" ]]

  docker rmi ${image}
  [ "$status" -eq 0 ]

  docker buildx prune -f
  [ "$status" -eq 0 ]

  docker buildx rm
  [ "$status" -eq 0 ]

  docker_stop $syscont

  rm $file
}

# Test docker buildx SBOM generation inside a sysbox container.
#
# The sbom scanner receives the scanned snapshot as an overlay mount in its OCI
# spec. runc init applies that mount after unsharing its pid-ns and before
# mounting a new procfs, so the sysbox-fs nsenter agent serving it sees a /proc
# that belongs to the parent pid-ns. That used to make the agent fail to load
# its capabilities and panic, and the mount came back EINVAL. See
# nestybox/sysbox#1048.
@test "docker buildx build with sbom inside sysbox container" {

  cat << EOF > ${file}
FROM ${CTR_IMG_REPO}/alpine
RUN apk update
CMD ["echo","Image created"]
EOF

  local syscont=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile ${CTR_IMG_REPO}/ubuntu-jammy-systemd-docker:latest tail -f /dev/null)

  wait_for_inner_dockerd $syscont

  docker exec $syscont sh -c "docker buildx version"
  if [ "$status" -ne 0 ]; then
	  docker_stop $syscont
	  rm $file
	  skip "docker buildx not supported by the inner docker"
  fi

  # The sbom scanner only runs under a buildkit-in-a-container builder; the
  # default "docker" driver rejects attestations outright.
  docker exec $syscont sh -c "docker buildx create --name sbom-builder --driver docker-container --use"
  [ "$status" -eq 0 ]

  docker exec $syscont sh -c "docker buildx inspect --bootstrap"
  [ "$status" -eq 0 ]

  # Output to cacheonly: attestations can't be loaded into the classic image
  # store, and the scan (the part under test) runs either way.
  docker exec $syscont sh -c "cd /mnt && docker buildx build --sbom=true -o type=cacheonly ."
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "invalid argument" ]]

  docker exec $syscont sh -c "docker buildx rm sbom-builder"
  [ "$status" -eq 0 ]

  docker_stop $syscont

  rm $file
}
