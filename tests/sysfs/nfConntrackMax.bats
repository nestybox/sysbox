# Testing of handler for /proc/sys/net/netfilter/nf_conntrack_max entry.

load ../helpers/setup
load ../helpers/fs
load ../helpers/run

# Container name.
SYSCONT_NAME=""

# Current nf_conntrack_max value defined in host fs.
NF_CONNTRACK_CUR_VAL=""

# nf_conntrack_max value to set inside container (lowwer than host-fs value).
NF_CONNTRACK_LOW_VAL=""

# nf_conntrack_max value to set inside container (higher than host-fs value).
NF_CONNTRACK_HIGH_VAL=""

function setup() {
  setup_busybox

  # Define nf_conntrack_max values to utilize during testing.
  run cat /proc/sys/net/netfilter/nf_conntrack_max
  [ "$status" -eq 0 ]
  NF_CONNTRACK_CUR_VAL=$output
  NF_CONNTRACK_LOW_VAL=$((NF_CONNTRACK_CUR_VAL - 100))
  NF_CONNTRACK_HIGH_VAL=$((NF_CONNTRACK_CUR_VAL + 100))
}

function teardown() {
  teardown_busybox
}

# Lookup/Getattr operation.
@test "nf_conntrack_max lookup() operation" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "ls -lrt /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  verify_root_rw "${output}"
}

# Read operation.
@test "nf_conntrack_max read() operation" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  [ "$output" = $NF_CONNTRACK_CUR_VAL ]
}

# Write a value lower than the current host-fs number.
@test "nf_conntrack_max write() operation (lower value)" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "echo $NF_CONNTRACK_LOW_VAL > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  runc exec test_busybox sh -c \
    "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ "$output" = $NF_CONNTRACK_LOW_VAL ]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /proc/sys/net/netfilter/nf_conntrack_max
  [ "$status" -eq 0 ]
  [ "$output" = $NF_CONNTRACK_CUR_VAL ]
}

# Write a value higher than the current host-fs number.
@test "nf_conntrack_max write() operation (higher value)" {
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  runc exec test_busybox sh -c \
    "echo $NF_CONNTRACK_HIGH_VAL > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  runc exec test_busybox sh -c \
    "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ "$output" = $NF_CONNTRACK_HIGH_VAL ]

  # Read from host-fs and verify that its value has been modified and it
  # matches the one being pushed above.
  run cat /proc/sys/net/netfilter/nf_conntrack_max
  [ "$status" -eq 0 ]
  [ "$output" = $NF_CONNTRACK_HIGH_VAL ]
}
