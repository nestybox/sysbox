#!/usr/bin/env bats

#
# Verify running a mysql container inside a sys container
#

load ../../helpers/run

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_mysql() {
  # it takes ~30 secs for the mysql container to reach "healthy" status
  retry_run 40 2 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"healthy\"\""
}

@test "l2 mysql basic" {

  skip "unstable"

  # Deploys a mysql container inside the sys container and verifies
  # mysql works

  # this mysql script will be passed to the mysql inner container
  cat << EOF > ${HOME}/mysql-scr.txt
CREATE DATABASE sample_db;
USE sample_db
CREATE TABLE pet (name VARCHAR(20), owner VARCHAR(20), species VARCHAR(20), sex CHAR(1), birth DATE, death DATE);
INSERT INTO pet VALUES ('Puffball','Diane','hamster','f','1999-03-30',NULL);
SELECT * FROM pet;
EOF

  # launch sys container; bind-mount the mysql script into it
  SYSCONT_NAME=$(docker_run --rm \
                   --mount type=bind,source="${HOME}"/mysql-scr.txt,target=/mysql-scr.txt \
                   nestybox/test-syscont tail -f /dev/null)

  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # launch the inner mysql container; bind-mount the mysql script into it
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/mysql_server_5.6.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name mysql1 \
                                     --mount type=bind,source=/mysql-scr.txt,target=/mysql-scr.txt \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     mysql/mysql-server:5.6"
  [ "$status" -eq 0 ]

  wait_for_inner_mysql

  docker exec "$SYSCONT_NAME" sh -c "docker exec mysql1 sh -c \"mysql < /mysql-scr.txt\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "name".+"owner".+"species".+"sex".+"birth".+"death" ]]
  [[ "${lines[1]}" =~ "Puffball".+"Diane".+"hamster".+"f".+"1999-03-30".+"NULL" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  rm ${HOME}/mysql-scr.txt
}

@test "l2 mysql client-server" {

  skip "unstable"

  # Deploys mysql server and client containers inside the sys
  # container and verifies mysql client can access the server.
  #
  # Note: decided to use mysql 5.6 server to avoid 'caching_sha2_password' problem
  # (see https://tableplus.com/blog/2018/07/failed-to-load-caching-sha2-password-authentication-plugin-solved.html)
  # it's possible to use mysqel 8.0 server, but then the client must be a
  # ubuntu image which is a bit too heavy for an already painfully slow test.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/test-syscont tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge mysql-net"
  [ "$status" -eq 0 ]

  # launch an inner mysql server container; connect it to the network;
  # allow connections from any host without password
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/mysql_server_5.6.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name mysql-server \
                                     --network mysql-net \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     -e MYSQL_ROOT_HOST=% \
                                     mysql/mysql-server:5.6"
  [ "$status" -eq 0 ]

  wait_for_inner_mysql

  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/alpine_3.10.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name mysql-client \
                                     --network mysql-net \
                                     alpine:3.10 tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec mysql-client sh -c \"apk update && apk add mysql-client\""
  [ "$status" -eq 0 ]


  # use the mysql client to create and query a database on the server
  docker exec "$SYSCONT_NAME" sh -c "docker exec mysql-client sh -c \"echo 'SHOW DATABASES;' | mysql -h mysql-server\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Database" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
