#!/usr/bin/env bats

#
# Verify running a fluentd container inside a sys container
#

load ../../helpers/run

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_inner_fluentd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
}

@test "l2 fluentd basic" {

  # Inside the sys container, deploys fluentd logger container and verifies
  # another container can send logs to it.

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/sys-container:ubuntu-plus-docker tail -f /dev/null)

  # launch docker inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # create a docker user-defined bridge network inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "docker network create --driver bridge fluentd-net"
  [ "$status" -eq 0 ]

  # create a dir on the sys container where the fluentd container will dump its logs
  # (must be writeable by all; fluentd is not running a root inside the container)
  docker exec "$SYSCONT_NAME" sh -c "mkdir -p /fluentd/log"
  docker exec "$SYSCONT_NAME" sh -c "chmod 777 /fluentd/log"

  # launch the inner fluentd container
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --rm --name fluentd \
                                     --network fluentd-net \
                                     -v /fluentd/log:/fluentd/log \
                                     fluent/fluentd:edge"
  [ "$status" -eq 0 ]

  wait_for_inner_fluentd

  docker exec "$SYSCONT_NAME" sh -c "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd"
  [ "$status" -eq 0 ]

  fluentd_ip=$output

  # generate a stdout log; should be sent to the fluentd container
  docker exec "$SYSCONT_NAME" sh -c "docker run --name logger \
                                     --network fluentd-net \
                                     --log-driver=fluentd \
                                     --log-opt tag=\"docker.{{.ID}}\" \
                                     --log-opt fluentd-address=$fluentd_ip:24224 \
                                     python:alpine echo Hello"
  [ "$status" -eq 0 ]

  # verify that fluentd container got the log
  docker exec "$SYSCONT_NAME" sh -c "tail -1 /fluentd/log/docker.log | grep Hello"
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"container_name":"/logger"' ]]
  [[ "$output" =~ '"log":"Hello"' ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
