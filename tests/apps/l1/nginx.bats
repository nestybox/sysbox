#!/usr/bin/env bats

#
# Verify running nginx inside a sys container
#

load ../../helpers/run
load ../../helpers/docker
load ../../helpers/sysbox-health
load ../../helpers/environment

export iface_mtu=$(egress_iface_mtu)

function teardown() {
  sysbox_log_check
}

function wait_for_nginx() {
  retry_run 5 1 eval "__docker ps --format \"{{.Status}}\" | grep \"Up\""
}

@test "l1 nginx basic" {

  # Deploys an nginx container with sysbox-runc

  # this html file will be passed to the nginx container via a bind-mount
  #
  # Note that we place it in /root which has 700 permissions; this is
  # a requirement imposed by sysbox when using uid-shifting: the bind
  # source must be within a path searchable by true root only.

  tmpdir="/root/nginx"
  mkdir -p ${tmpdir}

  cat << EOF > ${tmpdir}/index.html
<html>
<header><title>test</title></header>
<body>
Nginx Test!
</body>
</html>
EOF

  # launch the sys container; bind-mount the index.html into it
  SYSCONT_NAME=$(docker_run \
                   --mount type=bind,source=${tmpdir},target=/usr/share/nginx/html \
                   -p 8080:80 \
                   ${CTR_IMG_REPO}/nginx:latest)

  wait_for_nginx

  # verify the nginx container is up and running
  run wget -O ${tmpdir}/result.html http://localhost:8080
  [ "$status" -eq 0 ]

  run grep Nginx ${tmpdir}/result.html
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Nginx Test!" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]
  docker rm "$SYSCONT_NAME"
  [ "$status" -eq 0 ]
  rm -rf ${tmpdir}
}

@test "l1 nginx client-server" {

  # Deploys nginx server and client sys containers and verifies nginx
  # client can access the server.

  docker network create --driver bridge -o "com.docker.network.driver.mtu"="${iface_mtu}" nginx-net
  [ "$status" -eq 0 ]

  SERVER=$(docker_run -d --name nginx-server --network nginx-net ${CTR_IMG_REPO}/nginx:latest)
  [ "$status" -eq 0 ]

  wait_for_nginx

  CLIENT=$(docker_run -d --name nginx-client --network nginx-net ${CTR_IMG_REPO}/busybox:latest tail -f /dev/null)
  [ "$status" -eq 0 ]

  docker exec nginx-client sh -c "wget nginx-server:80"
  [ "$status" -eq 0 ]

  docker exec nginx-client sh -c "grep nginx index.html"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "<title>Welcome to nginx!</title>" ]]

  # cleanup

  docker_stop "$CLIENT"
  [ "$status" -eq 0 ]
  docker rm "$CLIENT"
  [ "$status" -eq 0 ]

  docker_stop "$SERVER"
  [ "$status" -eq 0 ]
  docker rm "$SERVER"
  [ "$status" -eq 0 ]

  docker network rm nginx-net
  [ "$status" -eq 0 ]
}
