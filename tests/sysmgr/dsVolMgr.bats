#!/usr/bin/env bats

#
# Integration test for the sysvisor-mgr docker-store volume manager
#

load ../helpers/run

@test "dsVolMgr basic" {

  SYSCONT_NAME=$(docker_run --rm nestybox/sys-container:debian-plus-docker tail -f /dev/null)

  #
  # verify things look good inside the sys container
  #

  # "/var/lib/docker" should be mounted to "/var/lib/sysvisor/docker/<syscont-name>"; note
  # that in the privileged test container the "/var/lib/sysvisor" is itself a mount-point,
  # so it won't show up in findmnt; thus we just grep for "docker/<syscont-name>"
  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"/var/lib/docker\" | grep \"docker/$SYSCONT_NAME\""
  [ "$status" -eq 0 ]

  # ownership of "/var/lib/docker" should be root:root
  docker exec "$SYSCONT_NAME" sh -c "stat /var/lib/docker | grep Uid"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "Access: (0700/drwx------)  Uid: (    0/    root)   Gid: (    0/    root)" ]]

  #
  # verify things look good on the host
  #

  # there should be a dir with the container's name under /var/lib/sysvisor/docker
  run ls /var/lib/sysvisor/docker/
  [ "$status" -eq 0 ]
  [[ ${lines[0]} =~ "$SYSCONT_NAME" ]]

  # and that dir should have ownership matching the sysvisor user
  run sh -c "cat /etc/subuid | grep sysvisor | cut -d\":\" -f2"
  [ "$status" -eq 0 ]
  SYSVISOR_UID="$output"

  run sh -c "stat /var/lib/sysvisor/docker/\"$SYSCONT_NAME\"* | grep Uid | grep \"$SYSVISOR_UID\""
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
}

@test "dsVolMgr persistence" {

  # Verify the sys container docker-store vol persists across container
  # start-stop-start events

  SYSCONT_NAME=$(docker_run nestybox/sys-container:debian-plus-docker tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "echo data > /var/lib/docker/test"
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]

  docker start "$SYSCONT_NAME"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "cat /var/lib/docker/test"
  [ "$status" -eq 0 ]
  [[ "$output" == "data" ]]

  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]

  docker rm "$SYSCONT_NAME"
  [ "$status" -eq 0 ]
}

@test "dsVolMgr non-persistence" {

  # Verify the sys container docker-store vol is removed when a
  # container is removed

  SYSCONT_NAME=$(docker_run nestybox/sys-container:debian-plus-docker tail -f /dev/null)

  # short ID -> full ID
  run sh -c "docker inspect \"$SYSCONT_NAME\" | jq '.[0] | .Id' | sed 's/\"//g'"
  [ "$status" -eq 0 ]
  sc_id="$output"

  docker exec "$SYSCONT_NAME" sh -c "echo data > /var/lib/docker/test"
  [ "$status" -eq 0 ]

  run cat "/var/lib/sysvisor/docker/$sc_id/test"
  [ "$status" -eq 0 ]
  [[ "$output" == "data" ]]

  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]

  run cat "/var/lib/sysvisor/docker/$sc_id/test"
  [ "$status" -eq 0 ]

  docker rm "$SYSCONT_NAME"

  run cat "/var/lib/sysvisor/docker/$sc_id/test"
  [ "$status" -eq 1 ]

  run cat "/var/lib/sysvisor/docker/$sc_id"
  [ "$status" -eq 1 ]
}

@test "dsVolMgr consecutive restart" {

  SYSCONT_NAME=$(docker_run nestybox/sys-container:debian-plus-docker tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "echo data > /var/lib/docker/test"
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]

  for i in $(seq 1 5); do
    docker start "$SYSCONT_NAME"
    [ "$status" -eq 0 ]

    docker exec "$SYSCONT_NAME" sh -c "cat /var/lib/docker/test"
    [ "$status" -eq 0 ]
    [[ "$output" == "data" ]]

    docker_stop "$SYSCONT_NAME"
    [ "$status" -eq 0 ]
  done

  docker rm "$SYSCONT_NAME"
}

#@test "sys-mgr dsVolMgr copy-up" {
  #
  # TODO: verify dsVolMgr copy-up by creating a sys container image with contents in /var/lib/docker
  # and checking that the contents are copied to the /var/lib/sysvisor/docker/<syscont-name> and
  # that they have the correct ownership. There is a dsVolMgr unit test that verifies this already,
  # but an integration test would be good too.
  #
#}
