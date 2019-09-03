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
                   nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

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

@test "l2 mysql client-server" {

  # Deploys mysql server and client containers inside the sys
  # container and verifies mysql client can access the server.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge mysql-net"
  [ "$status" -eq 0 ]

  # launch an inner mysql server container; connect it to the network;
  # allow connections from any host without password
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name mysql-server \
                                     --network mysql-net \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     -e MYSQL_ROOT_HOST=% \
                                     mysql/mysql-server:latest"
  [ "$status" -eq 0 ]

  wait_for_inner_mysql

  # launch an inner mysql client container; connect it to the network;
  # must use ubuntu image instead of debian as it has a recent version
  # of the mysql-client (older versions fail to connect due to lack of
  # 'caching_sha2_password' plugin).
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name mysql-client \
                                     --network mysql-net \
                                     ubuntu:latest tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec mysql-client sh -c \"apt-get update && apt-get install -y mysql-client\""
  [ "$status" -eq 0 ]

  # use the mysql client to create and query a database on the server
  docker exec "$SYSCONT_NAME" sh -c "docker exec mysql-client sh -c \"echo 'SHOW DATABASES;' | mysql -h mysql-server\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Database" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
