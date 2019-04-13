# Test to verify that resources exposed via /proc/sys/net inside a sys container are namespaced

load helpers

function setup_syscont() {
  run docker run --runtime=sysvisor-runc --rm -d --hostname syscont debian:latest tail -f /dev/null
  [ "$status" -eq 0 ]
  SYSCONT_NAME="$output"
}

function teardown_syscont() {
  run docker stop "$SYSCONT_NAME"
}

function setup() {
  teardown_syscont
  setup_syscont
}

function teardown() {
  teardown_syscont
}

@test "/proc/sys/net/ipv6/conf/all/disable_ipv6" {
  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6
  [ "$status" -eq 0 ]
  HOST_VAL="$output"

  run docker exec "$SYSCONT_NAME" sh -c "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run docker exec "$SYSCONT_NAME" sh -c "echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  run docker exec "$SYSCONT_NAME" sh -c "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6
  [ "$status" -eq 0 ]
  [ "$output" -eq "$HOST_VAL" ]

  run docker exec "$SYSCONT_NAME" sh -c "echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]

  run docker exec "$SYSCONT_NAME" sh -c "cat /proc/sys/net/ipv6/conf/all/disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run cat /proc/sys/net/ipv6/conf/all/disable_ipv6
  [ "$status" -eq 0 ]
  [ "$output" -eq "$HOST_VAL" ]
}
