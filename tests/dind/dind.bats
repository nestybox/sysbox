# Basic tests running docker *inside* a system container

load ../helpers

function setup() {
  setup_syscont
}

function teardown() {
  teardown_syscont
}

function wait_for_nested_dockerd {
  retry 10 1 eval "docker exec $SYSCONT_NAME docker ps"
}

@test "basic sys container" {
  run docker exec "$SYSCONT_NAME" hostname
  [ "$status" -eq 0 ]
  [ "$output" = "syscont" ]
}

@test "basic nested docker" {
  run docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  run docker exec "$SYSCONT_NAME" sh -c "docker run hello-world | grep \"Hello from Docker!\""
  [ "$status" -eq 0 ]
}

@test "nested busybox" {
  run docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  run docker exec "$SYSCONT_NAME" sh -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  run docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  run docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]
}
