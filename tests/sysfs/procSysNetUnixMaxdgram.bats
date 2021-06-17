# Testing of handler for /proc/sys/net/unix/max_dgram_qlen entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Current max_dgram_qlen value defined in host fs.
MAX_DGRAM_QLEN_CUR_VAL=""

# max_dgram_qlen value to set inside container (lowwer than host-fs value).
MAX_DGRAM_QLEN_LOW_VAL=""

# max_dgram_qlen value to set inside container (higher than host-fs value).
MAX_DGRAM_QLEN_HIGH_VAL=""

function setup() {
  setup_busybox

  # Define max_dgram_qlen values to utilize during testing.
  run cat /proc/sys/net/unix/max_dgram_qlen
  [ "$status" -eq 0 ]
  MAX_DGRAM_QLEN_CUR_VAL=$output
  MAX_DGRAM_QLEN_LOW_VAL=$((MAX_DGRAM_QLEN_CUR_VAL - 100))
  MAX_DGRAM_QLEN_HIGH_VAL=$((MAX_DGRAM_QLEN_CUR_VAL + 100))
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/net/unix/max_dgram_qlen lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /proc/sys/net/unix/max_dgram_qlen"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  verify_root_rw "${output}"
}

# Read operation.
@test "/proc/sys/net/unix/max_dgram_qlen read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "cat /proc/sys/net/unix/max_dgram_qlen"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  [ "$output" = $MAX_DGRAM_QLEN_CUR_VAL ]
}

# Write a value lower than the current host-fs number.
@test "/proc/sys/net/unix/max_dgram_qlen write() operation (lower value)" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo $MAX_DGRAM_QLEN_LOW_VAL > /proc/sys/net/unix/max_dgram_qlen"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/net/unix/max_dgram_qlen"
  [ "$status" -eq 0 ]
  [ "$output" = $MAX_DGRAM_QLEN_LOW_VAL ]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /proc/sys/net/unix/max_dgram_qlen
  [ "$status" -eq 0 ]
  [ "$output" = $MAX_DGRAM_QLEN_CUR_VAL ]
}

# Write a value higher than the current host-fs number.
@test "/proc/sys/net/unix/max_dgram_qlen write() operation (higher value)" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo $MAX_DGRAM_QLEN_HIGH_VAL > /proc/sys/net/unix/max_dgram_qlen"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/net/unix/max_dgram_qlen"
  [ "$status" -eq 0 ]
  [ "$output" = $MAX_DGRAM_QLEN_HIGH_VAL ]

  # Read from host-fs and verify that its value has been modified and it
  # matches the one being pushed above.
  run cat /proc/sys/net/unix/max_dgram_qlen
  [ "$status" -eq 0 ]
  [ "$output" = $MAX_DGRAM_QLEN_HIGH_VAL ]
}
