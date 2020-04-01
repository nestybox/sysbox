#!/usr/bin/env bats

# Testing of procSwaps handler.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

# /proc/swap header
PROC_SWAPS_HEADER="Filename                                Type            Size    Used    Priority"

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "procSwaps lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/swaps"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}

# Read operation.
@test "procSwaps read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # File content should only display the /proc/swap 'header'. No other line
  # should be present to indicate that swap has been disabled within sys
  # containers.
  sv_runc exec syscont sh -c \
    "cat /proc/swaps"
  [ "$status" -eq 0 ]
  [[ "$output" = $PROC_SWAPS_HEADER ]]
}

# Write operation.
@test "procSwaps write() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo 1 > /proc/swaps"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Input/output error" ]]
}
