#!/usr/bin/env bats

#
# Basic tests running docker inside a system container
#

load ../helpers/run
load ../helpers/docker
load ../helpers/dind
load ../helpers/sysbox
load ../helpers/environment
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "dind basic" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  local inner_docker_graphdriver=$(get_inner_docker_graphdriver)

  docker exec "$syscont" sh -c "grep \"graphdriver(s)=$inner_docker_graphdriver\" /var/log/dockerd.log"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "dind official image" {
	local dind_img="docker:24-dind"

	docker pull $dind_img
	docker network create some-network

	syscont=$(docker_run --name some-docker -d \
								--network some-network --network-alias docker \
								-e DOCKER_TLS_CERTDIR=/certs \
								-v some-docker-certs-ca:/certs/ca \
								-v some-docker-certs-client:/certs/client \
								$dind_img)

	docker run --rm --network some-network \
			 -e DOCKER_TLS_CERTDIR=/certs \
			 -v some-docker-certs-client:/certs/client:ro \
			 docker:latest pull -q nginx

	# cleanup
	docker_stop "$syscont"
	docker rm "$syscont"
	docker network rm some-network
	docker image rm $dind_img
}

# Same as dind official, but with Sysbox configured to disallow unmounts of
# immutable container mounts. In the past we had a bug where dind would fail in
# this scenario when the inner Docker engine (v24+) would execute a pivot-root
# while setting up the container.
@test "dind official (w/ allow-immutable-unmounts=false)" {
	local dind_img="docker:24-dind"

	sysbox_stop
	sysbox_start -t --allow-immutable-unmounts=false

	docker pull $dind_img
	docker network create some-network

	syscont=$(docker_run --name some-docker -d \
								--network some-network --network-alias docker \
								-e DOCKER_TLS_CERTDIR=/certs \
								-v some-docker-certs-ca:/certs/ca \
								-v some-docker-certs-client:/certs/client \
								$dind_img)

	docker run --rm --network some-network \
			 -e DOCKER_TLS_CERTDIR=/certs \
			 -v some-docker-certs-client:/certs/client:ro \
			 docker:latest pull -q nginx

	# cleanup
	docker_stop "$syscont"
	docker rm "$syscont"
	docker network rm some-network
	docker image rm $dind_img

	sysbox_stop
	sysbox_start -t
}

@test "dind busybox" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  local inner_docker_graphdriver=$(get_inner_docker_graphdriver)

  docker exec "$syscont" sh -c "grep \"graphdriver(s)=$inner_docker_graphdriver\" /var/log/dockerd.log"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$syscont" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$syscont"
}

@test "dind docker build" {

  # this dockerfile will be passed into the system container via a bind-mount
  file="/root/Dockerfile"

  cat << EOF > ${file}
FROM ${CTR_IMG_REPO}/alpine
MAINTAINER Nestybox
RUN apk update && apk add nginx
COPY . /root
EXPOSE 8080
CMD ["echo","Image created"]
EOF

  local syscont=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  local inner_docker_graphdriver=$(get_inner_docker_graphdriver)

  docker exec "$syscont" sh -c "grep \"graphdriver(s)=$inner_docker_graphdriver\" /var/log/dockerd.log"
  [ "$status" -eq 0 ]

  image="test_nginx"

  docker exec "$syscont" sh -c "cd /mnt && docker build -t ${image} ."
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run ${image}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Image created" ]]

  docker_stop "$syscont"
  docker image rm ${image}
  rm ${file}
}

@test "dind docker with non-default data-root" {

  # Create a new docker image with a custom docker config.
  pushd .
  cd tests/dind
  docker build -t sc-with-non-default-docker-data-root:latest -f Dockerfile.docker-data-root .
  [ "$status" -eq 0 ]

  docker image prune -f
  [ "$status" -eq 0 ]
  popd

  # Launch a sys container.
  local syscont=$(docker_run --rm sc-with-non-default-docker-data-root:latest tail -f /dev/null)

  # Verify that the default '/var/lib/docker' mountpoint has now been replaced
  # by the the new docker data-root entry.
  docker exec "$syscont" sh -c "mount | egrep -q \"on \/var\/lib\/docker\""
  [ "$status" -ne 0 ]
  docker exec "$syscont" sh -c "mount | egrep -q \"on \/var\/lib\/different-docker-data-root\""
  [ "$status" -eq 0 ]

  # Initialize docker and verify that the new data-root has been honored.

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker info | egrep -q \"different-docker-data-root\""
  [ "$status" -eq 0 ]

  # Verify that content can be properly stored in the new data-root by fetching
  # a new container image, and by checking that an inner container operates as
  # expected.
  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont="$output"

  docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # Cleaning up.
  docker_stop "$syscont"
  docker image rm sc-with-non-default-docker-data-root:latest
  docker image prune -f
}

@test "dind with docker official image" {

  # Pre-cleanup
  docker network rm some-network
  docker volume rm some-docker-certs-ca
  docker volume rm some-docker-certs-client

  # Setup
  docker network create some-network
  [ "$status" -eq 0 ]

  # Launch docker:dind image with Sysbox (i.e., docker engine container), per
  # https://hub.docker.com/_/docker. Notice we don't need the `--privileged`
  # flag anymore.
  local syscont=$(docker_run --rm --name some-docker \
									  --network some-network --network-alias docker \
									  -e DOCKER_TLS_CERTDIR=/certs \
									  -v some-docker-certs-ca:/certs/ca \
									  -v some-docker-certs-client:/certs/client \
									  docker:dind)

  wait_for_inner_dockerd $syscont

  # Launch docker CLI container with Sysbox
  local client=$(docker_run --rm --network some-network \
									 -e DOCKER_TLS_CERTDIR=/certs \
									 -v some-docker-certs-client:/certs/client:ro \
									 docker:latest version)

  # Verify the inner docker is using the correct graph driver (e.g., overlayfs, not vfs)
  local inner_docker_graphdriver=$(get_inner_docker_graphdriver)

  docker logs "$syscont"
  [ "$status" -eq 0 ]

  echo $output | grep "graphdriver=$inner_docker_graphdriver"

  # Verify we can launch an inner container
  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_container="$output"

  docker exec "$syscont" sh -c "docker exec $inner_container sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # cleanup
  docker_stop "$client"
  docker_stop "$syscont"

  docker network rm some-network
  [ "$status" -eq 0 ]
  docker volume rm some-docker-certs-ca
  [ "$status" -eq 0 ]
  docker volume rm some-docker-certs-client
  [ "$status" -eq 0 ]
}
