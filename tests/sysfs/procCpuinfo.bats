#!/usr/bin/env bats

# Testing of procCpuinfo handler.

load ../helpers
load helpers

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox
}

# Lookup/Getattr operation.
@test "procCpuinfo lookup() operation" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  verify_proc_ro test_busybox proc/cpuinfo
}
