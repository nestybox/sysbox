#!/usr/bin/env bats

#
# Verify running a elasticSearch container inside a sys container
#

load ../../helpers/run

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_elasticSearch() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "l2 elasticSearch basic" {

  # Inside the sys container, deploys an elasticSearch container and verifies
  # another container can send logs to it.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/test-syscont tail -f /dev/null)

  # launch docker inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge elasticSearch-net"
  [ "$status" -eq 0 ]

  # launch the inner elasticSearch container
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/elasticsearch_5.6.16-alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name elasticSearch \
                                     --net elasticSearch-net \
                                     -p 9200:9200 -p 9300:9300 \
                                     -e \"discovery.type=single-node\" elasticsearch:5.6.16-alpine"
  [ "$status" -eq 0 ]

  wait_for_inner_elasticSearch

  # launch a client container
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/alpine_3.10.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name client \
                                     --network elasticSearch-net \
                                     alpine:3.10 tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec client sh -c \"apk update && apk add curl\""
  [ "$status" -eq 0 ]

  sleep 6

  docker exec "$SYSCONT_NAME" sh -c "docker exec client sh -c \"curl -s -X GET \"elasticSearch:9200\"\""
  [ "$status" -eq 0 ]
  [[ "${lines[2]}" =~ "cluster_name".+"elasticsearch" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
