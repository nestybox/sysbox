# Testing of handler for /sys/devices/virtual/dmi/id/product_uuid entry.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Default cap_last_cap value in host fs.
SYS_DMI_PRODUCT_UUID_DEFAULT_VAL=""

function setup() {
  setup_busybox

  # Define default cap_last_cap value to utilize during testing.
  run cat /sys/devices/virtual/dmi/id/product_uuid
  [ "$status" -eq 0 ]
  # Skip the last 12 characters of the product_uuid as it will differ between the
  # host and the sys containers. Refer to sysbox-fs/handlers/implementations/sysDevicesVirtualDmiId.go
  # for details.
  SYS_DMI_PRODUCT_UUID_DEFAULT_VAL=${output::-12}
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/sys/devices/virtual/dmi/id/product_uuid lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 0 ]

  verify_perm_owner "-r--------" "root" "root" "${output}"
}

# Read operation.
@test "/sys/devices/virtual/dmi/id/product_uuid read() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "cat /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 0 ]

  # Read value should match the first 25 chars of the existing host-fs
  # figure.
  [[ "$output" =~ $SYS_DMI_PRODUCT_UUID_DEFAULT_VAL ]]
}

# Verify that write operation is not allowed.
@test "/sys/devices/virtual/dmi/id/product_uuid write() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "echo 1 > /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Permission denied" ]]

  # Read value back and verify that it's matching the original one.
  sv_runc exec syscont sh -c \
    "cat /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 0 ]
  [[ "$output" =~ $SYS_DMI_PRODUCT_UUID_DEFAULT_VAL ]]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /sys/devices/virtual/dmi/id/product_uuid
  [ "$status" -eq 0 ]
  [[ "$output" =~ $SYS_DMI_PRODUCT_UUID_DEFAULT_VAL ]]
}
