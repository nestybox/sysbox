# Testing of handler for /proc/sys/kernel/panic_on_oops entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Default panic_on_oops value in host fs (0).
KERNEL_PANIC_OOPS_DEFAULT_VAL=""

# Valid panic_on_oops value (>= 0 && <= 1).
KERNEL_PANIC_OOPS_VALID_VAL="1"

function setup() {
  setup_busybox

  # Define default panic_on_oops value to utilize during testing.
  run cat /proc/sys/kernel/panic_on_oops
  [ "$status" -eq 0 ]
  KERNEL_PANIC_OOPS_DEFAULT_VAL=$output
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/kernel/panic_on_oops lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /proc/sys/kernel/panic_on_oops"
  [ "$status" -eq 0 ]

  verify_root_rw "${output}"
}

# Read operation.
@test "/proc/sys/kernel/panic_on_oops read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "cat /proc/sys/kernel/panic_on_oops"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  [ "$output" = $KERNEL_PANIC_OOPS_DEFAULT_VAL ]
}

# Write a valid value different from default one (0).
@test "/proc/sys/kernel/panic_on_oops write() operation (valid value)" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo $KERNEL_PANIC_OOPS_VALID_VAL > /proc/sys/kernel/panic_on_oops"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/kernel/panic_on_oops"
  [ "$status" -eq 0 ]
  [ "$output" = $KERNEL_PANIC_OOPS_VALID_VAL ]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /proc/sys/kernel/panic_on_oops
  [ "$status" -eq 0 ]
  [ "$output" = $KERNEL_PANIC_OOPS_DEFAULT_VAL ]
}
