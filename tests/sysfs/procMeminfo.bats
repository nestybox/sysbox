#!/usr/bin/env bats

# Testing of procMeminfo handler.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Applies the given jq filter to the container's spec.
function update_spec() {
  jq "$1" config.json > config.json.tmp
  mv config.json.tmp config.json
}

# Lookup/Getattr operation.
@test "procMeminfo lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/meminfo"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}

# Read operation with a memory limit.
@test "procMeminfo read() operation with memory limit" {
  update_spec '.linux.resources.memory.limit = 268435456'

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "grep '^MemTotal:' /proc/meminfo | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 262144 ]

  sv_runc exec syscont sh -c "grep '^MemAvailable:' /proc/meminfo | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  [ "$output" -le 262144 ]
}

# Reads in small chunks see consistent content.
@test "procMeminfo read() operation in small chunks" {
  update_spec '.linux.resources.memory.limit = 268435456'

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # Every line must be well-formed, even though values change between reads.
  sv_runc exec syscont sh -c "dd if=/proc/meminfo bs=16 2>/dev/null | grep -cvE '^[A-Za-z0-9_()]+: +[0-9]+( kB)?\$'"
  [ "$output" -eq 0 ]

  sv_runc exec syscont sh -c "dd if=/proc/meminfo bs=16 2>/dev/null | grep '^MemTotal:' | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 262144 ]
}

# Read operation without a memory limit shows the host's memory.
@test "procMeminfo read() operation without memory limit" {
  hostMemTotal=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "grep '^MemTotal:' /proc/meminfo | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$hostMemTotal" ]
}

# Write operation.
@test "procMeminfo write() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "echo 1 > /proc/meminfo"
  [ "$status" -eq 1 ]
}
