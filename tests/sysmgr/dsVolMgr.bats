# integration test for the syvisor-mgr docker-store volume manager

load ../helpers

function setup() {
  docker_run
}

function teardown() {
  docker_stop
}

@test "sysvisor-mgr dsVolMgr" {

  #
  # verify things look good inside the sys container
  #

  # "/var/lib/docker" should be mounted to "/var/lib/sysvisor/docker/<syscont-name>"; note
  # that in the privileged test container the "/var/lib/sysvisor" is itself a mount-point,
  # so it won't show up in findmnt; thus we just grep for "docker/<syscont-name>"
  run docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"/var/lib/docker\" | grep \"docker/$SYSCONT_NAME\""
  [ "$status" -eq 0 ]

  # ownership of "/var/lib/docker" should be root:root
  run docker exec "$SYSCONT_NAME" sh -c "stat /var/lib/docker | grep Uid"
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
}

#@test "sysvisor-mgr dsVolMgr copy-up" {
  #
  # TODO: verify dsVolMgr copy-up by creating a sys container image with contents in /var/lib/docker
  # and checking that the contents are copied to the /var/lib/sysvisor/docker/<syscont-name> and
  # that they have the correct ownership. There is a dsVolMgr unit test that verifies this already,
  # but an integration test would be good too.
  #
#}
