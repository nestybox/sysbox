#!/usr/bin/env bats

#
# Verify running a postgres container inside a sys container
#

load ../../helpers/run
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_postgres() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "l2 postgres basic" {

  # Deploys a postgres container inside the sys container and verifies
  # postgres works

  # launch sys container; bind-mount the postgres script into it
  SYSCONT_NAME=$(docker_run --rm nestybox/test-syscont:latest tail -f /dev/null)

  # must choose "overlay" driver to avoid an "overlay2" driver bug
  # (https://stackoverflow.com/questions/45731683/docker-pull-operation-not-permitted)
  docker exec -d "$SYSCONT_NAME" sh -c "dockerd --storage-driver=\"overlay\"> /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # launch the inner postgres container; bind-mount the postgres script into it
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/postgres_alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name postgres1 postgres:alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_postgres
  sleep 5

  docker exec "$SYSCONT_NAME" sh -c "docker exec postgres1 sh -c 'psql -U postgres -c \\\\l'"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "List of databases" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}

@test "l2 postgres client-server" {

  # Deploys postgres server and client containers inside the sys
  # container and verifies postgres client can access the server.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/test-syscont:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$SYSCONT_NAME" sh -c "dockerd --storage-driver=\"overlay\"> /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge postgres-net"
  [ "$status" -eq 0 ]

  # launch an inner postgres server container; connect it to the network.
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/postgres_alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name postgres-server \
                                     --network postgres-net \
                                     postgres:alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_postgres

  # launch an inner postgres client container; connect it to the network.
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name postgres-client \
                                     --network postgres-net \
                                     postgres:alpine"
  [ "$status" -eq 0 ]

  # use the postgres client to create and query a database on the server
  docker exec "$SYSCONT_NAME" sh -c "docker exec postgres-client sh -c 'psql -h postgres-server -U postgres -c \\\\l'"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "List of databases" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
