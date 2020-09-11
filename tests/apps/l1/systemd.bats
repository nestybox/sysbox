#!/usr/bin/env bats

#
# Verify proper operation of a systemd within a sysbox container.
#

load ../../helpers/run
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function wait_for_init() {
  #
  # For systemd to be deemed as fully initialized, we must have at least
  # these four processes running.
  #
  # admin@sys-cont:~$ ps -ef | grep systemd
  # root       273     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-journald
  # systemd+   481     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-resolved
  # message+   844     1  0 Oct22 ?        00:00:00 /usr/bin/dbus-daemon --system --systemd-activation
  # root       871     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-logind
  #

  # XXX: For some reason the following retry is not working under
  # bats, which complains with "BATS_ERROR_STACK_TRACE: bad array
  # subscript" every so often. It's related to the pipe into grep.
  # As a work-around, we just wait for a few seconds for Systemd to
  # initialize.

  #retry 10 1 __docker exec "$SYSCONT_NAME" \
    #    sh -c "ps -ef | egrep systemd | wc -l | egrep [4-9]+"

  sleep 15
}

function check_systemd_mounts() {
  #
  # Check that the following resources are properly mounted to satisfy systemd
  # requirements:
  #
  # - /run                tmpfs   tmpfs    rw
  # - /run/lock           tmpfs   tmpfs    rw
  # - /tmp                tmpfs   tmpfs    rw
  # - /sys/kernel/config  tmpfs   tmpfs    rw
  # - /sys/kernel/debug   tmpfs   tmpfs    rw
  #
  docker exec "$SYSCONT_NAME" sh -c \
         "findmnt | egrep -e \"\/run .*tmpfs.*rw\" \
                   -e \"\/run\/lock .*tmpfs.*rw\" \
                   -e \"\/tmp .*tmpfs.*rw\" \
                   -e \"\/sys\/kernel\/config.*tmpfs.*rw\" \
                   -e \"\/sys\/kernel\/debug.*tmpfs.*rw\" \
                   | wc -l | egrep -q 5"

  [ "$status" -eq 0 ]
}

@test "systemd ubuntu bionic" {

  # Launch systemd container.
  SYSCONT_NAME=$(docker_run -d --rm --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd nestybox/ubuntu-bionic-systemd)

  wait_for_init

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$SYSCONT_NAME" sh -c "systemctl status"
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ "State: running" ]]

  # Verify that systemd's required resources are properly mounted.
  check_systemd_mounts

  # Verify that the hostname was properly set during container initialization,
  # which would confirm that 'hostnamectl' feature and its systemd dependencies
  # (i.e. dbus) are working as expected.
  docker exec "$SYSCONT_NAME" sh -c \
         "hostnamectl | egrep -q \"hostname: sys-cont-systemd\""
  [ "$status" -eq 0 ]

  # verify virtualization type
  docker exec "$SYSCONT_NAME" systemd-detect-virt
  [ "$status" -eq 0 ]
  [[ "$output" == "container-other" ]]

  # Restart a systemd service (journald) and verify it returns to 'running'
  # state.
  docker exec "$SYSCONT_NAME" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" systemctl restart systemd-journald.service
  [ "$status" -eq 0 ]

  sleep 2

  docker exec "$SYSCONT_NAME" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  # Cleanup
  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]
}

@test "systemd ubuntu focal" {

  # In ubuntu focal, systemd-resolved requires /proc/kcore to be
  # exposed inside the container (i.e., not masked with a /dev/null
  # bind mount), otherwise systemd fails to initialize.

  # Launch systemd container.
  SYSCONT_NAME=$(docker_run -d --rm --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd nestybox/ubuntu-focal-systemd)

  wait_for_init

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$SYSCONT_NAME" sh -c "systemctl status"
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ "State: running" ]]

  # Verify that systemd's required resources are properly mounted.
  check_systemd_mounts

  # Verify that the hostname was properly set during container initialization,
  # which would confirm that 'hostnamectl' feature and its systemd dependencies
  # (i.e. dbus) are working as expected.
  docker exec "$SYSCONT_NAME" sh -c \
         "hostnamectl | egrep -q \"hostname: sys-cont-systemd\""
  [ "$status" -eq 0 ]

  # verify virtualization type
  docker exec "$SYSCONT_NAME" systemd-detect-virt
  [ "$status" -eq 0 ]
  [[ "$output" == "container-other" ]]

  # Restart a systemd service (journald) and verify it returns to 'running'
  # state.
  docker exec "$SYSCONT_NAME" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" systemctl restart systemd-journald.service
  [ "$status" -eq 0 ]

  sleep 2

  docker exec "$SYSCONT_NAME" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  # Cleanup
  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]
}

@test "systemd mount overlaps" {

  docker volume create testVol
  [ "$status" -eq 0 ]

  # Launch systemd container.
  SYSCONT_NAME=$(docker_run -d --rm \
                            --mount source=testVol,destination=/run \
                            --mount source=testVol,destination=/run/lock \
                            --mount source=testVol,destination=/tmp \
                            --mount source=testVol,destination=/sys/kernel/config \
                            --mount source=testVol,destination=/sys/kernel/debug \
                            --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd nestybox/ubuntu-bionic-systemd)

  wait_for_init

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$SYSCONT_NAME" sh -c "systemctl status"
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ "State: running" ]]

  # Verify that mount overlaps have been identified and replaced as per systemd
  # demands.
  check_systemd_mounts

  # Cleanup
  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]

  docker volume rm testVol
}

@test "systemd /proc exposure" {

  # Verify that /proc nodes that we expose for systemd (/proc/kcore,
  # /proc/kallsyms, /proc/kmsg) do not present a security hole.

  SYSCONT_NAME=$(docker_run -d --rm --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd nestybox/ubuntu-focal-systemd)

  wait_for_init

  docker exec "$SYSCONT_NAME" sh -c "systemctl status"
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ "State: running" ]]

  docker exec "$SYSCONT_NAME" sh -c "cat /proc/kcore"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Permission denied" ]]

  docker exec "$SYSCONT_NAME" sh -c "cat /proc/kmsg"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Permission denied" ]]

  docker exec "$SYSCONT_NAME" sh -c "cat /proc/kallsyms | head -n 10 | cut -d ' ' -f1"
  [ "$status" -eq 0 ]

  for line in "${lines[@]}"; do
    [[ "$line" == "0000000000000000" ]]
  done

  # Cleanup
  docker_stop "$SYSCONT_NAME"
  [ "$status" -eq 0 ]
}
