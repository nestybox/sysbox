# Testing of handler for /proc/sys/kernel/ngroups_max entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Default ngroups_max value in host fs.
KERNEL_NGROUPS_MAX_DEFAULT_VAL=""

function setup() {
  setup_busybox

  # Define default ngroups_max value to utilize during testing.
  run cat /proc/sys/kernel/ngroups_max
  [ "$status" -eq 0 ]
  KERNEL_NGROUPS_MAX_DEFAULT_VAL=$output
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/kernel/ngroups_max lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /proc/sys/kernel/ngroups_max"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}

# Read operation.
@test "/proc/sys/kernel/ngroups_max read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "cat /proc/sys/kernel/ngroups_max"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  [ "$output" = $KERNEL_NGROUPS_MAX_DEFAULT_VAL ]
}

# Verify that write operation is not allowed.
@test "/proc/sys/kernel/ngroups_max Write() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo 1 > /proc/sys/kernel/ngroups_max"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Permission denied" ]]

  # Read value back and verify that it's matching the original one.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/kernel/ngroups_max"
  [ "$status" -eq 0 ]
  [ "$output" = $KERNEL_NGROUPS_MAX_DEFAULT_VAL ]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /proc/sys/kernel/ngroups_max
  [ "$status" -eq 0 ]
  [ "$output" = $KERNEL_NGROUPS_MAX_DEFAULT_VAL ]
}
