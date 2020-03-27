#!/usr/bin/env bats

#
# Testing of procUptime handler.
#

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

function setup() {
  setup_busybox

  # Obtain the container creation time.
  run cat /proc/uptime
  [ "$status" -eq 0 ]
  hostUptimeOutput="${lines[0]}"
  CNTR_START_TIMESTAMP=`echo ${hostUptimeOutput} | cut -d'.' -f 1`
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "procUptime lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/uptime"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}

# Read operation.
@test "procUptime read() operation" {

  # Let's sleep a bit to obtain a meaningful (!= zero) uptime.
  sleep 3

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat /proc/uptime"
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
