#!/usr/bin/env bats

#
# Verify running a wordpress container inside a sys container
#

load ../../helpers/run
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function wait_for_inner_dockerd() {
  local syscont=$1
  retry_run 10 1 eval "__docker exec $syscont docker ps"
}

@test "l2 wordpress basic" {

  # Deploy a wordpress container inside the sys container and verifies it works.

  # launch a sys container; we use a ubuntu-based sys container to work-around sysbox issue #270.
  local syscont=$(docker_run --rm --hostname sc nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # create a docker user-defined bridge network inside the sys container
  docker exec "$syscont" sh -c "docker network create --driver bridge -o \"com.docker.network.driver.mtu\"=\"1460\" wp-net"
  [ "$status" -eq 0 ]

  # launch an inner database (mysql) container; required by wordpress; we use
  # mysql version 5.6 as the latest (8.0) is not compatible with wordpress.
  #docker exec "$syscont" sh -c "docker load -i /root/img/mysql_server_5.6.tar"
  docker exec "$syscont" sh -c "docker run -d --name mysql \
                                     --network wp-net \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     -e MYSQL_ROOT_HOST=% \
                                     mysql/mysql-server:5.7"
  [ "$status" -eq 0 ]

  # launch an inner wordpress container
  docker exec "$syscont" sh -c "docker run -d --name wp \
                                     --network wp-net \
                                     -e WORDPRESS_DB_HOST=mysql \
                                     -p 8080:80 \
                                     wordpress"
  [ "$status" -eq 0 ]

  # verify the wordpress container is up and running
  docker exec "$syscont" sh -c "wget http://localhost:8080"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "grep wordpress /index.html"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "https://wordpress.org" ]]

  # cleanup
  docker_stop "$syscont"
}
