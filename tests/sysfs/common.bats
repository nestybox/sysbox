#!/usr/bin/env bats

#
# Testing of common handler.
#
# We will make use of ipv6_disable procfs entry to test this handler.

load ../helpers/setup
load ../helpers/fs
load ../helpers/run

# IPv6 constants.
IPV6_ENABLED="0"
IPV6_DISABLED="1"

function setup() {
  setup_busybox

  # The testcases in this file originally assumed that IPv6 is enabled in the
  # host fs. However, that's not a valid assumption for all the scenarios, as
  # these testcases can be potentially launched within a privileged container,
  # where IPv6 functionality is disabled by default. For the time being, i'll
  # assume that the testcases in this file will be exclusively executed from
  # within a privilege container, and as such, IPv6 is disabled in the context
  # that spawns these testcases.
  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6
  [ "$status" -eq 0 ]
  [ "$output" = $IPV6_DISABLED ]
}

function teardown() {
  teardown_busybox
}

# Lookup/Getattr operation.
@test "disable_ipv6 lookup() operation" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c "ls -l /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  run verify_root_rw "$output"
  [ "$status" -eq 0 ]
}

# Read operation.
@test "disable_ipv6 read() operation" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  # By default ipv6 should be disabled within a system container.
  [ "$output" = $IPV6_DISABLED ]
}

# Activate ipv6 within system container.
@test "disable_ipv6 write() operation (activation)" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "echo $IPV6_ENABLED > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's the expected one.
  runc exec test_busybox sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = $IPV6_ENABLED ]

  # Read from host-fs/privilege-container and verify that its value hasn't
  # been modified -- IPV6 is disabled.
  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6
  [ "$status" -eq 0 ]
  [ "$output" = $IPV6_DISABLED ]
}

# Deactivate ipv6 within system container.
@test "disable_ipv6 write() operation (de-activation)" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "echo $IPV6_DISABLED > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed -- IPV6 is now disabled.
  runc exec test_busybox sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = $IPV6_DISABLED ]

  # Read from host-fs and verify that IPV6 setting has not changed --
  # IPV6 continues to be disabled.
  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6
  [ "$status" -eq 0 ]
  [ "$output" = $IPV6_DISABLED ]
}
