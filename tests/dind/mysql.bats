#!/usr/bin/env bats

#
# Verify running a mysql container inside a sys container
#

load ../helpers/run

function wait_for_inner_dockerd {
  retry_run 10 1 eval "docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_mysql {
  # it can take a while for the mysql container to reach "healthy" status
  retry_run 40 2 eval "docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"healthy\"\""
}

@test "dind mysql basic" {

  # this mysql script will be passed to the mysql inner container
  cat << EOF > ${HOME}/mysql-scr.txt
CREATE DATABASE sample_db;
USE sample_db
CREATE TABLE pet (name VARCHAR(20), owner VARCHAR(20), species VARCHAR(20), sex CHAR(1), birth DATE, death DATE);
INSERT INTO pet VALUES ('Puffball','Diane','hamster','f','1999-03-30',NULL);
SELECT * FROM pet;
EOF

  # launch sys container; bind-mount the mysql script into it
  SYSCONT_NAME=$(docker_run \
                   --mount type=bind,source="${HOME}"/mysql-scr.txt,target=/mysql-scr.txt \
                   nestybox/sys-container:debian-plus-docker tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # launch the inner mysql container; bind-mount the mysql script into it
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name mysql1 \
                                     --mount type=bind,source=/mysql-scr.txt,target=/mysql-scr.txt \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     mysql/mysql-server:latest"
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

@test "dind mysql client-server" {

  # launch a sys container

  # launch docker inside the sys container

  # create a docker user-defined bridge network

  # launch an inner mysql server container; connect it to the network

  # launch an inner mysql client container; connect it to the network

  # use the mysql client to create and query a database on the server

  # destroy the sys container
}
