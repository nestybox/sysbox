#!/usr/bin/env bats

#
# Verify running a wordpress container inside a sys container
#

load ../helpers/run

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "docker exec $SYSCONT_NAME docker ps"
}

@test "dind wordpress basic" {

  # Deploy a wordpress container inside the sys container and verifies it works.

  # launch a sys container; we use a ubuntu-based sys container to
  # work-around sysvisor issue #270.
  SYSCONT_NAME=$(docker_run --rm --hostname sc nestybox/sys-container:ubuntu-plus-docker tail -f /dev/null)

  # launch docker inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge wp-net"
  [ "$status" -eq 0 ]

  # launch an inner database (mysql) container; required by wordpress; we use
  # mysql version 5.7 as the latest (8.0) is not compatible with wordpress.
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name mysql \
                                     --network wp-net \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     -e MYSQL_ROOT_HOST=% \
                                     mysql/mysql-server:5.7"
  [ "$status" -eq 0 ]

  # launch an inner wordpress container
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name wp \
                                     --network wp-net \
                                     -e WORDPRESS_DB_HOST=mysql \
                                     -p 8080:80 \
                                     wordpress"
  [ "$status" -eq 0 ]

  # verify the wordpress container is up and running
  docker exec "$SYSCONT_NAME" sh -c "wget http://localhost:8080"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "grep wordpress /index.html"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "https://wordpress.org" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
