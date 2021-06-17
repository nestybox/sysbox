# Testing of handler for /proc/sys/vm/overcommit_memory entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Default overcommit_memory value in host fs (0).
VM_OVERCOMMIT_MEMORY_DEFAULT_VAL=""

# Valid overcommit_memory value (>= 0 && <= 2).
VM_OVERCOMMIT_MEMORY_VALID_VAL="2"

# Invalid overcommit_memory value (< 0 && > 2).
VM_OVERCOMMIT_MEMORY_INVALID_VAL="3"

function setup() {
  setup_busybox

  # Define overcommit_memory values to utilize during testing.
  run cat /proc/sys/vm/overcommit_memory
  [ "$status" -eq 0 ]
  VM_OVERCOMMIT_MEMORY_DEFAULT_VAL=$output
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/vm/overcommit_memory lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /proc/sys/vm/overcommit_memory"
  [ "$status" -eq 0 ]

  verify_root_rw "${output}"
}

# Read operation.
@test "/proc/sys/vm/overcommit_memory read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "cat /proc/sys/vm/overcommit_memory"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  [ "$output" = $VM_OVERCOMMIT_MEMORY_DEFAULT_VAL ]
}

# Write a valid value different from default one (0).
@test "/proc/sys/vm/overcommit_memory write() operation (valid value)" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo $VM_OVERCOMMIT_MEMORY_VALID_VAL > /proc/sys/vm/overcommit_memory"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/vm/overcommit_memory"
  [ "$status" -eq 0 ]
  [ "$output" = $VM_OVERCOMMIT_MEMORY_VALID_VAL ]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /proc/sys/vm/overcommit_memory
  [ "$status" -eq 0 ]
  [ "$output" = $VM_OVERCOMMIT_MEMORY_DEFAULT_VAL ]
}

# Write an invalid/unsupported value (< 0 && > 2).
@test "/proc/sys/vm/overcommit_memory write() operation (invalid value)" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo $VM_OVERCOMMIT_MEMORY_INVALID_VAL > /proc/sys/vm/overcommit_memory"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid argument" ]]

  # Read value back and verify that it's matching the default figure (0), and
  # not the latest one we attempted to write.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/vm/overcommit_memory"
  [ "$status" -eq 0 ]
  [ "$output" = $VM_OVERCOMMIT_MEMORY_DEFAULT_VAL ]

  # Read from host-fs and verify that its value has not been modified either.
  run cat /proc/sys/vm/overcommit_memory
  [ "$status" -eq 0 ]
  [ "$output" = $VM_OVERCOMMIT_MEMORY_DEFAULT_VAL ]
}
