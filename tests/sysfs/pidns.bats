#!/usr/bin/env bats

#
# Tests to verify sysbox-fs handling of accesses by processes at different pid namespace hierarchies
#

load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
}

@test "pid-ns hierarchy" {

  last_cap=$(cat /proc/sys/kernel/cap_last_cap)

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # one level down
  sv_runc exec syscont sh -c "unshare -p -f cat /proc/sys/kernel/cap_last_cap"
  [ "$status" -eq 0 ]
  [[ "$output" == "$last_cap" ]]

  # two levels down
  sv_runc exec syscont sh -c "unshare -p -f unshare -p -f cat /proc/sys/kernel/cap_last_cap"
  [ "$status" -eq 0 ]
  [[ "$output" == "$last_cap" ]]

  # three levels down
  sv_runc exec syscont sh -c "unshare -p -f unshare -p -f unshare -p -f cat /proc/sys/kernel/cap_last_cap"
  [ "$status" -eq 0 ]
  [[ "$output" == "$last_cap" ]]
}
