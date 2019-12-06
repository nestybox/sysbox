#!/usr/bin/env bats

# General tests of /sys handlers

load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
}

@test "sysfs remount" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  sv_runc exec syscont sh -c "mkdir /root/sys && mount -t sysfs sysfs /root/sys"
  [ "$status" -eq 0 ]
}
