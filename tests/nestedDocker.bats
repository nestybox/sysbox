# Basic tests running docker *inside* a system container

load helpers

SYSCONT_NAME=""

function setup_syscont() {
  run docker run --runtime=sysvisor-runc --rm -d --hostname syscont nestybox/sys-container:debian-plus-docker tail -f /dev/null
  [ "$status" -eq 0 ]

  run docker ps --format "{{.ID}}"
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

function wait_for_nested_dockerd {
  retry 5 2 eval "docker exec $SYSCONT_NAME docker ps"
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

  run docker exec "$SYSCONT_NAME" sh -c 'docker run hello-world | grep "Hello from Docker!"'
  [ "$status" -eq 0 ]
}
