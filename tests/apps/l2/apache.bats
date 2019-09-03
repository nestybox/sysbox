#!/usr/bin/env bats

#
# Verify running an apache container inside a sys container
#

load ../../helpers/run

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_apache() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "l2 apache basic" {

  # Deploys a apache container inside the sys container and verifies it works

  # this html file will be passed to the apache container
  cat << EOF > ${HOME}/index.html
<html>
<header><title>test</title></header>
<body>
Apache Test!
</body>
</html>
EOF

  # launch sys container; bind-mount the index.html into it
  SYSCONT_NAME=$(docker_run --rm \
                   --mount type=bind,source="${HOME}"/index.html,target=/html/index.html \
                   nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # launch the inner apache container; bind-mount the html directory.
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name apache \
                                     --mount type=bind,source=/html,target=/usr/local/apache2/htdocs/ \
                                     -p 8080:80 \
                                     httpd:latest"
  [ "$status" -eq 0 ]

  wait_for_inner_apache

  # verify the apache container is up and running
  docker exec "$SYSCONT_NAME" sh -c "wget http://localhost:8080"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "grep Apache /index.html"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Apache Test!" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  rm ${HOME}/index.html
}

@test "l2 apache client-server" {

  # Deploys apache server and client containers inside the sys
  # container and verifies apache client can access the server.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge apache-net"
  [ "$status" -eq 0 ]

  # launch an inner apache server container; connect it to the network;
  # allow connections from any host without password
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name apache-server \
                                     --network apache-net \
                                     httpd:latest"
  [ "$status" -eq 0 ]

  wait_for_inner_apache

  # launch an inner apache client container; connect it to the network;
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name apache-client \
                                     --network apache-net \
                                     busybox:latest tail -f /dev/null"
  [ "$status" -eq 0 ]

  # use the client to access the apache server
  docker exec "$SYSCONT_NAME" sh -c "docker exec apache-client sh -c \"wget apache-server:80\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec apache-client sh -c \"cat index.html\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec apache-client sh -c \"grep h1 index.html\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "It works" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
