#!/usr/bin/env bats

#
# Integration test to verify the operation of the Sysbox's devManager features
# for generic device interfaces.
#

load ../helpers/run
load ../helpers/fs
load ../helpers/ns
load ../helpers/docker
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
  setup_debian
}

function teardown() {
  teardown_debian syscont
  sysboxfs_health_check
}

sysbox_devices_host_path="/var/lib/sysbox/devices"

# "Present" or "Absent" devices are those that are/are-not present in the host's
# /dev directory.
#
# "Supported" or "Unsupported" devices are those that are/are-not supported/handled
# by the devMgr.

absent_unsupported_device_file="/tmp/absent_unsupported_device"

cat << EOF > ${absent_unsupported_device_file}
{
  "path": "/dev/blah",
  "type": "c",
  "major": 3,
  "minor": 195,
  "fileMode": 438,
  "uid": 0,
  "gid": 0
}
EOF

present_unsupported_device_file="/tmp/present_unsupported_device"

cat << EOF > ${present_unsupported_device_file}
{
  "path": "/dev/loop1",
  "type": "b",
  "major": 7,
  "minor": 1,
  "fileMode": 438,
  "uid": 0,
  "gid": 0
}
EOF

absent_supported_device_file="/tmp/absent_supported_device"

cat << EOF > ${absent_supported_device_file}
{
  "path": "/dev/nvidia1",
  "type": "c",
  "major": 195,
  "minor": 1,
  "fileMode": 438,
  "uid": 0,
  "gid": 0
}
EOF

present_supported_device_file="/tmp/present_supported_device"

cat << EOF > ${present_supported_device_file}
{
  "path": "/dev/net/tun",
  "type": "c",
  "major": 10,
  "minor": 200,
  "fileMode": 438,
  "uid": 0,
  "gid": 0
}
EOF

@test "absent device unsupported by devMgr" {
    setup_debian_spec_add_device ${absent_unsupported_device_file}

    sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
    [ "$status" -ne 0 ]
    [[ "$output" =~ "creating device nodes caused: no such file or directory" ]]
}

@test "present device unsupported by devMgr" {
    if ! stat /dev/loop1; then
        skip "/dev/loop1 not present in the host"
    fi

    setup_debian_spec_add_device ${present_unsupported_device_file}

    sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
    [ "$status" -eq 0 ]

    sv_runc exec syscont sh -c "stat /dev/loop1"
    [ "$status" -eq 0 ]

    sv_runc exec syscont sh -c "ls -l /dev/loop1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "brw-rw---- 1 nobody nogroup 7, 1" ]]
}

@test "absent device supported by devMgr" {
    setup_debian_spec_add_device ${absent_supported_device_file}

    sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
    [ "$status" -ne 0 ]
    [[ "$output" =~ "creating device nodes caused: no such file or directory" ]]
}

@test "present device supported by devMgr" {
    if ! stat /dev/net/tun; then
        skip "/dev/net/tun not present in the host"
    fi

    setup_debian_spec_add_device ${present_supported_device_file}

    sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
    [ "$status" -eq 0 ]

    sv_runc exec syscont sh -c "stat /dev/net/tun"
    [ "$status" -eq 0 ]

    # There's a pending issue in the devMgr's implementation that allows devices to be
    # created by default (i.e., /dev/net/tun) to utilize the uid/gid defined by the user
    # in the device spec. In these cases, the device is created with the device-spec's
    # uid/gids, and not with the uid/gid of the user namespace, so they shoow up as
    # owned by nobody/nogroup. This is a bug that needs to be fixed.
    sv_runc exec syscont sh -c "ls -l /dev/net/tun"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "crw-rw-rw- 1 nobody nogroup 10, 200" ]]
}
