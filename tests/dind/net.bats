#!/usr/bin/env bats

#
# Tests for docker networking inside a system container
#

load ../helpers/run
load ../helpers/net

SYSCONT_NAME=""

function setup() {
  SYSCONT_NAME=$(docker_run --rm nestybox/sys-container:debian-plus-docker tail -f /dev/null)
}

function teardown() {
  docker_stop "$SYSCONT_NAME"
}

function wait_for_nested_dockerd {
  retry_run 10 1 eval "docker exec $SYSCONT_NAME docker ps"
}

@test "dind bridge net" {

  # verify basic docker bridge networking inside a sys container
  # (based on https://docs.docker.com/network/network-tutorial-standalone/)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker network ls | awk '{ print \$2 \" \" \$4 }'"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" == "bridge local" ]
  [ "${lines[2]}" == "host local" ]
  [ "${lines[3]}" == "none local" ]

  docker exec "$SYSCONT_NAME" sh -c "ip a"
  [ "$status" -eq 0 ]

  sc_ip=$(parse_ip "$output" "eth0")
  sc_sub=$(parse_subnet "$output" "eth0")

  # spawn a couple of inner containers and check that their network config is fine
  for inner in alpine1 alpine2; do
    docker exec "$SYSCONT_NAME" sh -c "docker run -d --name $inner alpine tail -f /dev/null"
    [ "$status" -eq 0 ]

    docker exec "$SYSCONT_NAME" sh -c "docker exec $inner ip a"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" =~ "lo".+"<LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000" ]]
    [[ "${lines[2]}" =~ "inet 127.0.0.1/8 scope host lo" ]]
    [[ "${lines[6]}" =~ "eth0".+"<BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UP" ]]

    declare "${inner}_ip"=$(parse_ip "$output" "eth0")
    declare "${inner}_sub"=$(parse_subnet "$output" "eth0")
  done

  # verify subnets look ok
  [[ "$alpine1_sub" != "$sc_sub" ]]
  [[ "$alpine2_sub" != "$sc_sub" ]]
  [[ "$alpine1_sub" == "$alpine2_sub" ]]

  # verify the inner containers can ping each other by IP
  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine1 ping -c 2 $alpine2_ip"
  [ "$status" -eq 0 ]
  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine2 ping -c 2 $alpine1_ip"
  [ "$status" -eq 0 ]

  # verify the inner containers can't ping each other by name
  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine1 ping -c 2 alpine2"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]
  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine2 ping -c 2 alpine1"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]

  # test external connectivity of inner containers
  for inner in alpine1 alpine2; do
    docker exec "$SYSCONT_NAME" sh -c "docker exec $inner ping -c 2 google.com"
    [ "$status" -eq 0 ]

    docker exec "$SYSCONT_NAME" sh -c "docker exec $inner ping -c 2 $sc_ip"
    [ "$status" -eq 0 ]
  done
}

@test "dind user net" {

  # verify basic docker user-defined networking inside a sys container
  # (based on https://docs.docker.com/network/network-tutorial-standalone/)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "ip a"
  [ "$status" -eq 0 ]

  sc_ip=$(parse_ip "$output" "eth0")
  sc_sub=$(parse_subnet "$output" "eth0")

  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge alpine-net"
  [ "$status" -eq 0 ]

  # Create four inner containers; two of them are connected to apline-net;
  # one of them is connected to the default bridge net; one of them is
  # connected to both alpine-net and the default bridge net.
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name alpine1 --network alpine-net alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name alpine2 --network alpine-net alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name alpine3 alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name alpine4 --network alpine-net alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker network connect bridge alpine4"
  [ "$status" -eq 0 ]

  # get the IP for each
  for inner in alpine1 alpine2 alpine3 alpine4; do
    docker exec "$SYSCONT_NAME" sh -c "docker exec $inner ip a"
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
  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine1 ping -c 2 alpine2"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine1 ping -c 2 alpine4"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine1 ping -c 2 alpine1"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine1 ping -c 2 alpine3"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]

  # test connectivity on alpine4
  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine4 ping -c 2 alpine1"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine4 ping -c 2 alpine2"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine4 ping -c 2 alpine3"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ping: bad address" ]]

  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine4 ping -c 2 $alpine3_ip"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec alpine4 ping -c 2 alpine4"
  [ "$status" -eq 0 ]

  # test external connectivity
  for inner in alpine1 alpine2 alpine3 alpine4; do
    docker exec "$SYSCONT_NAME" sh -c "docker exec $inner ping -c 2 google.com"
    [ "$status" -eq 0 ]

    docker exec "$SYSCONT_NAME" sh -c "docker exec $inner ping -c 2 $sc_ip"
    [ "$status" -eq 0 ]
  done
}

@test "dind host net" {

  # verify basic docker host networking inside a sys container
  # (based on https://docs.docker.com/network/network-tutorial-standalone/)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run -d --network host --name my_nginx nginx"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "netstat -tulpn | grep :80"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tcp".+"0.0.0.0:80".+"LISTEN".+"nginx" ]]

  docker exec "$SYSCONT_NAME" sh -c "curl -s http://localhost:80 | grep \"<title>Welcome to nginx\!</title>\""
  [ "$status" -eq 0 ]
  [[ "$output" == "<title>Welcome to nginx!</title>" ]]
}

# @test "dind port map" {
#
#   # verify docker port mapping (from host->syscont, from
#   # syscont->inner-cont); access inner cont from host via mapped port.
#
# }
