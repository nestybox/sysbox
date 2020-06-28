#!/usr/bin/env bats

#
# Verify running a redis container inside a sys container
#

load ../../helpers/run
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_redis() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "l2 redis basic" {

  # Deploys a redis container inside the sys container and verifies
  # redis works

  # this redis script will be passed to the redis inner container
  cat << EOF > ${HOME}/redis-scr.txt
SET foo 100
INCR foo
GET foo
EOF

  # launch sys container; bind-mount the redis script into it
  SYSCONT_NAME=$(docker_run --rm \
                   --mount type=bind,source="${HOME}"/redis-scr.txt,target=/redis-scr.txt \
                   nestybox/test-syscont:latest tail -f /dev/null)

  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # launch the inner redis container; bind-mount the redis script into it
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/redis_5.0.5_alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name redis1 \
                                     --mount type=bind,source=/redis-scr.txt,target=/redis-scr.txt \
                                     redis:5.0.5-alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_redis

  docker exec "$SYSCONT_NAME" sh -c "docker exec redis1 sh -c \"cat /redis-scr.txt | redis-cli\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "OK" ]]
  [[ "${lines[1]}" == "101" ]]
  [[ "${lines[2]}" == "101" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  rm ${HOME}/redis-scr.txt
}

@test "l2 redis client-server" {

  # Deploys redis server and client containers inside the sys
  # container and verifies redis client can access the server.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/test-syscont:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge redis-net"
  [ "$status" -eq 0 ]

  # launch an inner redis server container; connect it to the network.
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/redis_5.0.5_alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name redis-server \
                                     --network redis-net \
                                     redis:5.0.5-alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_redis

  # launch an inner redis client container; connect it to the network.
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name redis-client \
                                     --network redis-net \
                                     redis:5.0.5-alpine"
  [ "$status" -eq 0 ]

  # use the redis client to create and query a database on the server
  docker exec "$SYSCONT_NAME" sh -c "docker exec redis-client sh -c \"redis-cli -h redis-server SET foo 100\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec redis-client sh -c \"redis-cli -h redis-server GET foo\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "100" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
