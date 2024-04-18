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

# Testcase #1.
#
# Test basic buildx operations within a sys container. In this scenario, we
# are relying on docker's extended functionality (buildx's default driver), so
# no external buildkit component is utilized here.
@test "L1 buildx + L1 docker-engine (docker driver)" {

  cat << EOF > ${file}
FROM ${CTR_IMG_REPO}/alpine
MAINTAINER Nestybox
RUN apk update && apk add nginx
COPY . /root
EXPOSE 8080
CMD ["echo","Image created"]
EOF

  syscont=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile ${CTR_IMG_REPO}/ubuntu-focal-systemd-docker:latest tail -f /dev/null)

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

# Testcase #2.
#
# Test basic buildkit features when this one is launched by Sysbox (i.e.,
# buildkit runs at L1 level).
@test "L0 buildx + L1 buildkit container (docker-container driver)" {

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

# Testcase #3.
#
# Test basic buildkit features when this one is launched within a sysbox container
# (i.e., buildkit runs at L2 level).
@test "L0 buildx + L2 buildkit container (docker-container driver)" {

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

  local syscont=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile ${CTR_IMG_REPO}/ubuntu-focal-systemd-docker:latest tail -f /dev/null)

  wait_for_inner_dockerd $syscont

  # Obtain sys container's ip address.
  docker exec $syscont bash -c "ip address show dev eth0 | grep inet | cut -d\"/\" -f1 | awk '{print \$2}'"
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
