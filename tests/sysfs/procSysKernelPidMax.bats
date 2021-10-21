# Testing of handler for /proc/sys/kernel/pid_max entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Default pid_max value in host fs.
KERNEL_PID_MAX_DEFAULT_VAL=""

function setup() {
  setup_busybox

  # Define default pid_max value to utilize during testing.
  run cat /proc/sys/kernel/pid_max
  [ "$status" -eq 0 ]

  KERNEL_PID_MAX_DEFAULT_VAL=$output
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/kernel/pid_max lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /proc/sys/kernel/pid_max"
  [ "$status" -eq 0 ]

  verify_root_rw "${output}"
}

# Read operation.
@test "/proc/sys/kernel/pid_max read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "cat /proc/sys/kernel/pid_max"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  [ "$output" = $KERNEL_PID_MAX_DEFAULT_VAL ]
}

# Verify that write operation is emulated
@test "/proc/sys/kernel/pid_max write() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo 1 > /proc/sys/kernel/pid_max"
  [ "$status" -eq 0 ]

  run cat /proc/sys/kernel/pid_max
  [ "$status" -eq 0 ]
  [ "$output" = $KERNEL_PID_MAX_DEFAULT_VAL ]

  # Test out of range value fails (max pid_max = 2^22)
  sv_runc exec syscont sh -c \
    "echo 4194305 > /proc/sys/kernel/pid_max"
  [ "$status" -eq 1 ]
}
