#!/usr/bin/env bats

#
# Testing of procUptime handler.
#

load ../helpers
load helpers

function setup() {
  setup_busybox

  # Obtain the container creation time.
  run cat /proc/uptime
  [ "$status" -eq 0 ]
  hostUptimeOutput="${lines[0]}"
  CNTR_START_TIMESTAMP=`echo ${hostUptimeOutput} | cut -d'.' -f 1`
}

function teardown() {
  teardown_busybox
}

# Lookup/Getattr operation.
@test "procUptime lookup() operation" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  verify_proc_ro test_busybox proc/uptime
}

# Read operation.
@test "procUptime read() operation" {

  # Let's sleep a bit to obtain a meaningful (!= zero) uptime.
  sleep 3

  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c "cat /proc/uptime"
  [ "$status" -eq 0 ]

  # Obtain the container uptime and add it to the container creation time. This
  # combined value should be slightly lower than the system uptime.
  cntrUptimeOutput="${lines[0]}"
  cntrUptime=`echo ${cntrUptimeOutput} | cut -d'.' -f 1`
  cntrStartPlusUptime=$(($CNTR_START_TIMESTAMP + $cntrUptime))
  hostUptime=`cut -d'.' -f 1 /proc/uptime`

  echo "cntrStartPlusUptime = ${cntrStartPlusUptime}"
  echo "hostUptime = ${hostUptime}"
  [ $cntrStartPlusUptime -le $hostUptime ]
}
