#!/usr/bin/env bats

# Testing of procPagetypeinfo handler.

load ../helpers/setup
load ../helpers/fs
load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox
}

# Lookup/Getattr operation.
@test "procPagetypeinfo lookup() operation" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c "ls -l /proc/pagetypeinfo"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}
