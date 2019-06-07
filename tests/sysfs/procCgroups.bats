# Testing of procCgroups handler.

load ../helpers

function setup() {
  setup_syscont
}

function teardown() {
  teardown_syscont
}

# Lookup/Getattr operation.
@test "procCgroups lookup() operation" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "ls -lrt /proc/cgroups"
  [ "$status" -eq 0 ]

  # Read value should match this substring.
  echo "lines = ${lines[0]}"
  [[ "${lines[0]}" =~ "-r--r--r-- 1 root root" ]]
}
