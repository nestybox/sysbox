#!/usr/bin/env bats

#
# Testing of common handler.
#
# We will make use of ipv6_disable procfs entry to test this handler.

load ../helpers/run
load ../helpers/fs

disable_ipv6=/proc/sys/net/ipv6/conf/all/disable_ipv6

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox
}

# lookup
@test "common handler: lookup" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  # disable_ipv6
  sv_runc exec test_busybox sh -c "ls -l $disable_ipv6"
  [ "$status" -eq 0 ]

  verify_root_rw "$output"
  [ "$status" -eq 0 ]
}

@test "common handler: disable_ipv6" {

  local enable="0"
  local disable="1"

  host_orig_val=$(cat $disable_ipv6)

  sv_runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  # By default ipv6 should be enabled within a system container
  # launched by sysvisor-runc directly (e.g., without docker) Note
  # that in system container launched with docker + sysvisor-runc,
  # docker (somehow) disables ipv6.
  sv_runc exec test_busybox sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$enable" ]

  # Disable ipv6 in system container and verify
  sv_runc exec test_busybox sh -c "echo $disable > $disable_ipv6"
  [ "$status" -eq 0 ]

  sv_runc exec test_busybox sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$disable" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat $disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]

  # Re-enable ipv6 within system container
  sv_runc exec test_busybox sh -c "echo $enable > $disable_ipv6"
  [ "$status" -eq 0 ]

  sv_runc exec test_busybox sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$enable" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat $disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]
}
