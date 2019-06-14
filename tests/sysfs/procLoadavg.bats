#!/usr/bin/env bats

# Testing of procLoadavg handler.

load ../helpers/fs
load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox
}

# Lookup/Getattr operation.
@test "procLoadavg lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  sv_runc exec test_busybox sh -c "ls -l /proc/loadavg"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}
