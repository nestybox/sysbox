# Testing of procDiskstats handler.

load ../helpers

function setup() {
  setup_syscont
}

function teardown() {
  teardown_syscont
}

# Lookup/Getattr operation.
@test "procDiskstats lookup() operation" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "ls -lrt /proc/diskstats"
  [ "$status" -eq 0 ]

  # Read value should match this substring.
  echo "lines = ${lines[0]}"
  [[ "${lines[0]}" =~ "-r--r--r-- 1 root root" ]]
}
