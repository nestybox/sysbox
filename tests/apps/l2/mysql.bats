#!/usr/bin/env bats

#
# Verify running a mysql container inside a sys container
#

load ../../helpers/run
load ../../helpers/docker
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function wait_for_inner_dockerd() {
  local syscont=$1
  retry_run 10 1 eval "__docker exec $syscont docker ps"
}

function wait_for_inner_mysql() {
  local syscont=$1
  # it takes ~30 secs for the mysql container to reach "healthy" status
  retry_run 40 2 eval "__docker exec $syscont sh -c \"docker ps --format \"{{.Status}}\" | grep \"healthy\"\""
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
  local syscont=$(docker_run --rm \
                   --mount type=bind,source="${HOME}"/mysql-scr.txt,target=/mysql-scr.txt \
                   ${CTR_IMG_REPO}/test-syscont tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # launch the inner mysql container; bind-mount the mysql script into it
  docker exec "$syscont" sh -c "docker load -i /root/img/mysql_server_8.0.tar"
  docker exec "$syscont" sh -c "docker run -d --name mysql1 \
                                     --mount type=bind,source=/mysql-scr.txt,target=/mysql-scr.txt \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     mysql/mysql-server:8.0"
  [ "$status" -eq 0 ]

  wait_for_inner_mysql $syscont

  docker exec "$syscont" sh -c "docker exec mysql1 sh -c \"mysql < /mysql-scr.txt\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "name".+"owner".+"species".+"sex".+"birth".+"death" ]]
  [[ "${lines[1]}" =~ "Puffball".+"Diane".+"hamster".+"f".+"1999-03-30".+"NULL" ]]

  # cleanup
  docker_stop "$syscont"
  rm ${HOME}/mysql-scr.txt
}

@test "l2 mysql client-server" {

  # Deploys mysql server and client containers inside the sys
  # container and verifies mysql client can access the server.
  #
  # Note: decided to use mysql 5.6 server to avoid 'caching_sha2_password' problem
  # (see https://tableplus.com/blog/2018/07/failed-to-load-caching-sha2-password-authentication-plugin-solved.html)
  # it's possible to use mysqel 8.0 server, but then the client must be a
  # ubuntu image which is a bit too heavy for an already painfully slow test.
  #
  # Update Jan 2022: I needed to deploy a more recent mysql-server release for
  # multi-arch support purposes (only amd64 image provided in 5.6). I fixed the
  # above issue by enabling this knob (--default-authentication-plugin=mysql_native_password)
  # to have mysql defaulting to the legacy password-based authentication.

  # launch a sys container
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/test-syscont tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # create a docker user-defined bridge network inside the sys container
  docker exec "$syscont" sh -c "docker network create --driver bridge mysql-net"
  [ "$status" -eq 0 ]

  # launch an inner mysql server container; connect it to the network;
  # allow connections from any host without password
  docker exec "$syscont" sh -c "docker load -i /root/img/mysql_server_8.0.tar"
  docker exec "$syscont" sh -c "docker run -d --name mysql-server \
                                     --network mysql-net \
                                     -e MYSQL_ALLOW_EMPTY_PASSWORD=true \
                                     -e MYSQL_LOG_CONSOLE=true \
                                     -e MYSQL_ROOT_HOST=% \
                                     mysql/mysql-server:8.0 \
				     --default-authentication-plugin=mysql_native_password"
  [ "$status" -eq 0 ]

  wait_for_inner_mysql $syscont

  docker exec "$syscont" sh -c "docker load -i /root/img/alpine_3.10.tar"
  docker exec "$syscont" sh -c "docker run -d --name mysql-client \
                                     --network mysql-net \
                                     alpine:3.10 tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec mysql-client sh -c \"apk update && apk add mysql-client\""
  [ "$status" -eq 0 ]


  # use the mysql client to create and query a database on the server
  docker exec "$syscont" sh -c "docker exec mysql-client sh -c \"echo 'SHOW DATABASES;' | mysql -h mysql-server\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Database" ]]

  # cleanup
  docker_stop "$syscont"
}
