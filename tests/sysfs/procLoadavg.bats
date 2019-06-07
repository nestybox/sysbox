# Testing of procLoadavg handler.

load ../helpers

function setup() {
  docker_run
}

function teardown() {
  docker_stop
}

# Lookup/Getattr operation.
@test "procLoadavg lookup() operation" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "ls -lrt /proc/loadavg"
  [ "$status" -eq 0 ]

  # Read value should match this substring.
  echo "lines = ${lines[0]}"
  [[ "${lines[0]}" =~ "-r--r--r-- 1 root root" ]]
}
