#!/usr/bin/env bats

#
# Verify running a elasticSearch container inside a sys container
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

function wait_for_inner_elasticSearch() {
  local syscont=$1
  retry_run 10 1 eval "__docker exec $syscont sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "l2 elasticSearch basic" {

  # NOTE: elasticSearch is *very* memory hungry: it eats >2GB of RAM
  # in this simple test. If you run it, make sure you have >= 4GB of
  # RAM in your machine.
  skip "Consumes > 2GB of RAM"

  # Inside the sys container, deploys an elasticSearch container and verifies
  # another container can send logs to it.

  # launch a sys container
  local syscont=$(docker_run --rm nestybox/test-syscont tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # create a docker user-defined bridge network inside the sys container
  docker exec "$syscont" sh -c "docker network create --driver bridge -o \"com.docker.network.driver.mtu\"=\"1460\" elasticSearch-net"
  [ "$status" -eq 0 ]

  # launch the inner elasticSearch container
  docker exec "$syscont" sh -c "docker load -i /root/img/elasticsearch_5.6.16-alpine.tar"
  docker exec "$syscont" sh -c "docker run -d --name elasticSearch \
                                     --net elasticSearch-net \
                                     -p 9200:9200 -p 9300:9300 \
                                     -e \"discovery.type=single-node\" elasticsearch:5.6.16-alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_elasticSearch $syscont

  # launch a client container
  docker exec "$syscont" sh -c "docker load -i /root/img/alpine_3.10.tar"
  docker exec "$syscont" sh -c "docker run -d --name client \
                                     --network elasticSearch-net \
                                     alpine:3.10 tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec client sh -c \"apk update && apk add curl\""
  [ "$status" -eq 0 ]

  sleep 10

  docker exec "$syscont" sh -c "docker exec client sh -c \"curl -s -X GET \"elasticSearch:9200\"\""
  [ "$status" -eq 0 ]
  [[ "${lines[2]}" =~ "cluster_name".+"elasticsearch" ]]

  # cleanup
  docker_stop "$syscont"
}
