# Testing of handler for /proc/sys/net/netfilter/nf_conntrack_max entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health
load ../helpers/environment

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
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/net/netfilter/nf_conntrack_max lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  verify_root_rw "${output}"
}

# Read operation.
@test "/proc/sys/net/netfilter/nf_conntrack_max read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value should match the existing host-fs figure.
  [ "$output" = $NF_CONNTRACK_CUR_VAL ]
}

# Write a value lower than the current host-fs number.
@test "/proc/sys/net/netfilter/nf_conntrack_max write() operation (lower value)" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo $NF_CONNTRACK_LOW_VAL > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ "$output" = $NF_CONNTRACK_LOW_VAL ]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /proc/sys/net/netfilter/nf_conntrack_max
  [ "$status" -eq 0 ]
  [ "$output" = $NF_CONNTRACK_CUR_VAL ]
}

# Write a value higher than the current host-fs number.
@test "/proc/sys/net/netfilter/nf_conntrack_max write() operation (higher value)" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo $NF_CONNTRACK_HIGH_VAL > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  # Read value back and verify that it's matching the same one previously
  # pushed.
  sv_runc exec syscont sh -c \
    "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ "$output" = $NF_CONNTRACK_HIGH_VAL ]

  # Read from host-fs and verify that its value has been modified and it
  # matches the one being pushed above.
  run cat /proc/sys/net/netfilter/nf_conntrack_max
  [ "$status" -eq 0 ]
  # Fedora kernel prevents write-access to this node from a non-init network ns.
  # Other distros allow it, for now. In these cases an EPERM should be received
  # above while trying to write to this node, but the sysbox-fs flag
  #  "--ignore-handler-errors" prevents it.
  [ $(get_distro) == "fedora" ] || [ "$output" = $NF_CONNTRACK_HIGH_VAL ]
}
