# Testing of procCpuinfo handler.

load ../helpers

# Container name.
SYSCONT_NAME=""

function setup_syscont() {
  run docker run --runtime=sysvisor-runc --rm -d --hostname syscont \
    nestybox/sys-container:debian-plus-docker tail -f /dev/null
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

# Lookup/Getattr operation.
@test "procCpuinfo lookup() operation" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "ls -lrt /proc/cpuinfo"
  [ "$status" -eq 0 ]

  # Read value should match this substring.
  echo "lines = ${lines[0]}"
  [[ "${lines[0]}" =~ "-r--r--r-- 1 root root" ]]
}