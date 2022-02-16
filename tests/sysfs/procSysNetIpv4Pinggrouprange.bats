# Testing of handler for /proc/sys/net/ipv4/ping_group_range entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Default ping_range_group value in sys-container's procfs.
KERNEL_PING_GROUP_RANGE_DEFAULT_VAL="65534	65534"

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/net/ipv4/ping_group_range lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -lrt /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 0 ]

  verify_root_rw "${output}"
}

# Read operation.
@test "/proc/sys/net/ipv4/ping_group_range read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 0 ]

  # Read value should match the expected default value.
  [[ "$output" == "$KERNEL_PING_GROUP_RANGE_DEFAULT_VAL" ]]
}

# Write operation.
@test "/proc/sys/net/ipv4/ping_group_range write() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # Attempt to write an unsupported range value.
  sv_runc exec syscont sh -c \
    "echo \"-1 65535\" > /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid argument" ]]

  # Attempt to write an unsupported range value.
  sv_runc exec syscont sh -c \
    "echo \"0 2147483648\" > /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid argument" ]]

  # Write range value beyond user-namespace boundaries. Verify that the stored
  # (cached) value corresponds to the one the user provided, and not the one
  # being pushed down to the kernel (65535).
  sv_runc exec syscont sh -c \
    "echo \"0 2147483647\" > /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 0 ]
  [[ "$output" == "0	2147483647" ]]

  local pid=$(pidof sh)
  run nsenter -t "$pid" -p -n -U cat /proc/sys/net/ipv4/ping_group_range
  [ "$status" -eq 0 ]
  [[ "$output" == "0	65535" ]]

  # Write a smaller, fully valid, range and verify that in this case the cached
  # and the kernel values match.
  sv_runc exec syscont sh -c \
    "echo \"1000 64000\" > /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat /proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 0 ]
  [[ "$output" = "1000	64000" ]]

  local pid=$(pidof sh)
  run nsenter -t "$pid" -p -n -U cat /proc/sys/net/ipv4/ping_group_range
  [ "$status" -eq 0 ]
  [[ "$output" == "1000	64000" ]]

  # Read from host-fs (test-priv-container) and verify that its value hasn't been
  # modified.
  run cat "/proc/sys/net/ipv4/ping_group_range"
  [ "$status" -eq 0 ]
  [ "$output" = "1	0" ]
}
