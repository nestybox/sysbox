# Testing of common handler.
#
# We will make use of ipv6_disable procfs entry to test this handler.

load ../helpers

# IPv6 constants.
IPV6_ENABLED="0"
IPV6_DISABLED="1"

function setup() {
  docker_run

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
  docker_stop
}

# Lookup/Getattr operation.
@test "disable_ipv6 lookup() operation" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "ls -lrt /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  # Read value should match this substring.
  [[ "${lines[0]}" =~ "-rw-r--r-- 1 root root" ]]
}

# Read operation.
@test "disable_ipv6 read() operation" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  # By default ipv6 should be disabled within a system container.
  [ "$output" = $IPV6_DISABLED ]
}

# Activate ipv6 within system container.
@test "disable_ipv6 write() operation (activation)" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "echo $IPV6_ENABLED > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's the expected one.
  run docker exec "$SYSCONT_NAME" sh -c \
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
  run docker exec "$SYSCONT_NAME" sh -c \
    "echo $IPV6_DISABLED > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed -- IPV6 is now disabled.
  run docker exec "$SYSCONT_NAME" sh -c \
    "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = $IPV6_DISABLED ]

  # Read from host-fs and verify that IPV6 setting has not changed --
  # IPV6 continues to be disabled.
  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6
  [ "$status" -eq 0 ]
  [ "$output" = $IPV6_DISABLED ]
}
