#!/usr/bin/env bats

#
# Verify running a elasticSearch container inside a sys container
#

load ../helpers/run

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_elasticSearch() {
  retry_run 40 2 eval "docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "dind elasticSearch basic" {

  # Inside the sys container, deploys an elasticSearch container and verifies
  # another container can send logs to it.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/sys-container:ubuntu-plus-docker tail -f /dev/null)

  # launch docker inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge elasticSearch-net"
  [ "$status" -eq 0 ]

  # launch the inner elasticSearch container (this image is slow to download, ~40 secs!)
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name elasticSearch \
                                     --net elasticSearch-net \
                                     -p 9200:9200 -p 9300:9300 \
                                     -e \"discovery.type=single-node\" elasticsearch:7.2.0"
  [ "$status" -eq 0 ]

  wait_for_inner_elasticSearch

  # launch a client container
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name client \
                                     --network elasticSearch-net \
                                     debian:latest tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec client sh -c \"apt-get update && apt-get install -y curl\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec client sh -c \"curl -s -X GET \"elasticSearch:9200\"\""
  [ "$status" -eq 0 ]
  [[ "${lines[2]}" =~ "cluster_name".+"docker-cluster" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
