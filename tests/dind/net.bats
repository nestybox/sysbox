#!/usr/bin/env bats

#
# Tests for docker-in-docker networking
#

load ../helpers/run
load ../helpers/net
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "dind default net" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # verify basic docker bridge networking inside a sys container
  # (based on https://docs.docker.com/network/network-tutorial-standalone/)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker network ls | awk '{ print \$2 \" \" \$4 }'"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" == "bridge local" ]
  [ "${lines[2]}" == "host local" ]
  [ "${lines[3]}" == "none local" ]

  docker exec "$syscont" sh -c "ip a"
  [ "$status" -eq 0 ]

  local sc_ip=$(parse_ip "$output" "eth0")
  local sc_sub=$(parse_subnet "$output" "eth0")

  # spawn a couple of inner containers and check that their network config is fine
  for inner in alpine1 alpine2; do
    docker exec "$syscont" sh -c "docker run -d --name $inner alpine tail -f /dev/null"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "docker exec $inner ip a"
    [ "$status" -eq 0 ]

    declare "${inner}_ip"=$(parse_ip "$output" "eth0")
    declare "${inner}_sub"=$(parse_subnet "$output" "eth0")
  done

  # verify subnets look ok
  [[ "$alpine1_sub" != "$sc_sub" ]]
  [[ "$alpine2_sub" != "$sc_sub" ]]
  [[ "$alpine1_sub" == "$alpine2_sub" ]]

  # verify the inner containers can ping each other by IP
  docker exec "$syscont" sh -c "docker exec alpine1 ping -c 2 $alpine2_ip"
  [ "$status" -eq 0 ]
  docker exec "$syscont" sh -c "docker exec alpine2 ping -c 2 $alpine1_ip"
  [ "$status" -eq 0 ]

  # verify the inner containers can't ping each other by name
  docker exec "$syscont" sh -c "docker exec alpine1 ping -c 2 alpine2"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]
  docker exec "$syscont" sh -c "docker exec alpine2 ping -c 2 alpine1"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]

  # test external connectivity of inner containers
  for inner in alpine1 alpine2; do
    docker exec "$syscont" sh -c "docker exec $inner ping -c 2 google.com"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "docker exec $inner ping -c 2 $sc_ip"
    [ "$status" -eq 0 ]
  done

  docker_stop "$syscont"
}

@test "dind user net" {

  # verify basic docker user-defined networking inside a sys container
  # (based on https://docs.docker.com/network/network-tutorial-standalone/)

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "ip a"
  [ "$status" -eq 0 ]

  local sc_ip=$(parse_ip "$output" "eth0")
  local sc_sub=$(parse_subnet "$output" "eth0")

  docker exec "$syscont" sh -c "docker network create --driver bridge alpine-net"
  [ "$status" -eq 0 ]

  # Create four inner containers; two of them are connected to apline-net;
  # one of them is connected to the default bridge net; one of them is
  # connected to both alpine-net and the default bridge net.
  docker exec "$syscont" sh -c "docker run -d --name alpine1 --network alpine-net alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name alpine2 --network alpine-net alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name alpine3 alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name alpine4 --network alpine-net alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker network connect bridge alpine4"
  [ "$status" -eq 0 ]

  # get the IP for each
  for inner in alpine1 alpine2 alpine3 alpine4; do
    docker exec "$syscont" sh -c "docker exec $inner ip a"
    [ "$status" -eq 0 ]
    declare "${inner}_ip"=$(parse_ip "$output" "eth0")
    declare "${inner}_sub"=$(parse_subnet "$output" "eth0")
  done

  # verify subnets look ok
  [[ "$alpine1_sub" != "$sc_sub" ]]
  [[ "$alpine2_sub" != "$sc_sub" ]]
  [[ "$alpine3_sub" != "$sc_sub" ]]
  [[ "$alpine4_sub" != "$sc_sub" ]]

  # test connectivity on alpine1 using container names (docker auto dns)
  docker exec "$syscont" sh -c "docker exec alpine1 ping -c 2 alpine2"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec alpine1 ping -c 2 alpine4"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec alpine1 ping -c 2 alpine1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec alpine1 ping -c 2 alpine3"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]

  # test connectivity on alpine4
  docker exec "$syscont" sh -c "docker exec alpine4 ping -c 2 alpine1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec alpine4 ping -c 2 alpine2"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec alpine4 ping -c 2 alpine3"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]

  docker exec "$syscont" sh -c "docker exec alpine4 ping -c 2 $alpine3_ip"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec alpine4 ping -c 2 alpine4"
  [ "$status" -eq 0 ]

  # test external connectivity
  for inner in alpine1 alpine2 alpine3 alpine4; do
    docker exec "$syscont" sh -c "docker exec $inner ping -c 2 google.com"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "docker exec $inner ping -c 2 $sc_ip"
    [ "$status" -eq 0 ]
  done

  docker_stop "$syscont"
}

@test "dind host net" {

  # verify basic docker host networking inside a sys container
  # (based on https://docs.docker.com/network/network-tutorial-standalone/)

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker run -d --network host --name my_nginx nginx"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "netstat -tulpn | grep :80"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tcp".+"0.0.0.0:80".+"LISTEN".+"nginx" ]]

  docker exec "$syscont" sh -c "curl -s http://localhost:80 | grep \"<title>Welcome to nginx\!</title>\""
  [ "$status" -eq 0 ]
  [[ "$output" == "<title>Welcome to nginx!</title>" ]]

  docker_stop "$syscont"
}

# @test "dind port map" {
#
#   # verify docker port mapping (from host->syscont, from
#   # syscont->inner-cont); access inner cont from host via mapped port.
#
# }
