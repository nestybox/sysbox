#!/usr/bin/env bats

# Testing of procLoadavg handler.

load ../helpers/fs
load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
}

# Lookup/Getattr operation.
@test "procLoadavg lookup() operation" {

  skip "not a sysvisor-fs mount yet"

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/loadavg"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}
