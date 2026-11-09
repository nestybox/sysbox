#!/usr/bin/env bats

# Testing of procCpuinfo and sysDevicesSystemCpuOnline handlers.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
  # The debian bundle (not busybox) is used here because the tests below need
  # glibc's getconf.
  setup_debian
}

function teardown() {
  teardown_debian syscont
  sysbox_log_check
}

# Applies the given jq filter to the container's spec.
function update_spec() {
  jq "$1" config.json > config.json.tmp
  mv config.json.tmp config.json
}

# Lookup/Getattr operation.
@test "procCpuinfo lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/cpuinfo"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}

# Read operation with a fractional CPU quota.
@test "procCpuinfo read() operation with cpu quota" {
  hostFirstCpu=$(cut -d',' -f1 /sys/devices/system/cpu/online | cut -d'-' -f1)

  update_spec '.linux.resources.cpu.quota = 50000 | .linux.resources.cpu.period = 100000'

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "grep -c '^processor' /proc/cpuinfo"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  sv_runc exec syscont sh -c "cat /sys/devices/system/cpu/online"
  [ "$status" -eq 0 ]
  [ "$output" == "$hostFirstCpu" ]

  # glibc counts the CPUs listed in /sys/devices/system/cpu/online
  sv_runc exec syscont sh -c "getconf _NPROCESSORS_ONLN"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

# Read operation with a cpuset keeps the host's CPU numbering.
@test "procCpuinfo read() operation with cpuset" {
  if [ $(nproc) -lt 2 ]; then
    skip "needs at least 2 host CPUs"
  fi

  update_spec '.linux.resources.cpu.cpus = "1"'

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "grep '^processor' /proc/cpuinfo | awk '{print \$3}'"
  [ "$status" -eq 0 ]
  [ "$output" == "1" ]

  sv_runc exec syscont sh -c "cat /sys/devices/system/cpu/online"
  [ "$status" -eq 0 ]
  [ "$output" == "1" ]
}

# Read operation without CPU limits shows the host's CPUs.
@test "procCpuinfo read() operation without cpu limits" {
  hostCpus=$(grep -c '^processor' /proc/cpuinfo)
  hostOnline=$(cat /sys/devices/system/cpu/online)

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "grep -c '^processor' /proc/cpuinfo"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$hostCpus" ]

  # Same content when read in small chunks.
  sv_runc exec syscont sh -c "dd if=/proc/cpuinfo bs=16 2>/dev/null | grep -c '^processor'"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$hostCpus" ]

  sv_runc exec syscont sh -c "cat /sys/devices/system/cpu/online"
  [ "$status" -eq 0 ]
  [ "$output" == "$hostOnline" ]
}

# Write operation.
@test "procCpuinfo write() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "echo 1 > /proc/cpuinfo"
  [ "$status" -ne 0 ]

  sv_runc exec syscont sh -c "echo 1 > /sys/devices/system/cpu/online"
  [ "$status" -ne 0 ]
}
