#!/usr/bin/env bats

#
# Verify running a nginx container inside a sys container
#

load ../../helpers/run

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_nginx() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "l2 nginx basic" {

  # Deploys a nginx container inside the sys container and verifies it works

  # this html file will be passed to the nginx container
  cat << EOF > ${HOME}/index.html
<html>
<header><title>test</title></header>
<body>
Nginx Test!
</body>
</html>
EOF

  # launch sys container; bind-mount the index.html into it
  SYSCONT_NAME=$(docker_run --rm \
                   --mount type=bind,source="${HOME}"/index.html,target=/html/index.html \
                   nestybox/test-syscont:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # launch the inner nginx container; bind-mount the html directory.
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/nginx_mainline_alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name nginx \
                                     --mount type=bind,source=/html,target=/usr/share/nginx/html,readonly \
                                     -p 8080:80 \
                                     nginx:mainline-alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_nginx

  # verify the nginx container is up and running
  docker exec "$SYSCONT_NAME" sh -c "wget http://localhost:8080"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "grep Nginx /index.html"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Nginx Test!" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  rm ${HOME}/index.html
}

@test "l2 nginx client-server" {

  # Deploys nginx server and client containers inside the sys
  # container and verifies nginx client can access the server.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/test-syscont:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge nginx-net"
  [ "$status" -eq 0 ]

  # launch an inner nginx server container; connect it to the network;
  # allow connections from any host without password
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/nginx_mainline_alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name nginx-server \
                                     --network nginx-net \
                                     nginx:mainline-alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_nginx

  # launch an inner nginx client container; connect it to the network;
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/alpine_3.10.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name nginx-client \
                                     --network nginx-net \
                                     alpine:3.10 tail -f /dev/null"
  [ "$status" -eq 0 ]

  # use the client to access the nginx server
  docker exec "$SYSCONT_NAME" sh -c "docker exec nginx-client sh -c \"wget nginx-server:80\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec nginx-client sh -c \"grep nginx index.html\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "<title>Welcome to nginx!</title>" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
