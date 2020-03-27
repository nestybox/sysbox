#!/usr/bin/env bats

#
# Verify running a telegraf container inside a sys container
#

load ../../helpers/run
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "l2 telegraf basic" {

  # Inside the sys container, deploys a telegraf container and verifies it's up & running

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm nestybox/test-syscont:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # prior to launching telegraf, we must run an influxdb container
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/influxdb_1.7-alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name influxdb -p 8083:8083 -p 8086:8086 influxdb"
  [ "$status" -eq 0 ]

  sleep 1

  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/telegraf-1.12-alpine.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --name telegraf --net=container:influxdb telegraf"
  [ "$status" -eq 0 ]

  sleep 1

  docker exec "$SYSCONT_NAME" sh -c "docker logs telegraf"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "Starting Telegraf" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
