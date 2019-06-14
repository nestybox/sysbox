#!/usr/bin/env bats

#
# Testing of common handler.
#
# We will make use of ipv6_disable procfs entry to test this handler.

load ../helpers/setup
load ../helpers/fs
load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox
}

# lookup
@test "common handler: lookup" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  # disable_ipv6
  runc exec test_busybox sh -c "ls -l /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  verify_root_rw "$output"
  [ "$status" -eq 0 ]
}

@test "common handler: disable_ipv6" {

  local ipv6_enabled="0"
  local ipv6_disabled="1"

  host_orig_val=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)

  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  # By default ipv6 should be enabled within a system container
  # launched by sysvisor-runc directly (e.g., without docker) Note
  # that in system container launched with docker + sysvisor-runc,
  # docker (somehow) disables ipv6.
  runc exec test_busybox sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$ipv6_enabled" ]

  # Disable ipv6 in system container and verify
  runc exec test_busybox sh -c \
    "echo $ipv6_disabled > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$ipv6_disabled" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]

  # Re-enable ipv6 within system container
  runc exec test_busybox sh -c \
    "echo $ipv6_enabled > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$ipv6_enabled" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]
}
