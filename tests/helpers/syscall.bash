#!/bin/bash

#
# syscall emulation test helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

# List of files or dirs under procfs emulated bys sysbox-fs
PROCFS_EMU=( "swaps" "sys" "uptime" )

# List of procfs files with read-only requirements as per OCI spec
PROCFS_RDONLY=( "bus" "fs" "irq" "sysrq-trigger" )

# List of procfs files that need to be masked as per OCI spec
PROCFS_MASKED=( "kcore" "keys" "timer_list" "sched_debug" )

# List of procfs files that need to be exposed as tmpfs mounts as per OCI spec
PROCFS_TMPFS=( "acpi" "scsi")

# verifies the given sys container path contains a procfs mount backed by sysbox-fs
function verify_syscont_procfs_mnt() {

  # argument check
  ! [[ "$#" < 2 ]]
  local syscont_name=$1
  local mnt_path=$2
  if [ $# -eq 3 ]; then
     local readonly=$3
  fi

  if [ -n "$readonly" ]; then
     opt=\(ro,
  fi

  docker exec "$syscont_name" bash -c "mount | grep \"proc on $mnt_path type proc $opt\""
  [ "$status" -eq 0 ]

  for node in "${PROCFS_EMU[@]}"; do
    docker exec "$syscont_name" bash -c "mount | grep $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse $opt" ]]
  done

  for node in "${PROCFS_RDONLY[@]}"; do
    docker exec "$syscont_name" bash -c "mount | grep $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "proc on $mnt_path/$node type proc (ro,relatime" ]]
  done

  #
  # Commenting these ones out to prevent testcases' outcome to diverge
  # depending on the test-container on which these ones are executed
  # (i.e. regular 'test' vs 'test-installer'). In the regular 'test'
  # container, "tmpfs" is mounted over the masked resources, whereas,
  # in the 'test-installer' case, is "udev" the fstype being mounted
  # due to the presence of systemd-udev daemon. To avoid differentiated
  # behaviors, we will comment this checkpoint for now.
  #
  # for node in "${PROCFS_MASKED[@]}"; do
  #   docker exec "$syscont_name" bash -c "mount | grep $mnt_path/$node"
  #   [ "$status" -eq 0 ]
  #   [[ "$output" =~ "udev on $mnt_path/$node type devtmpfs (rw,nosuid,relatime," ]]
  # done

  for node in "${PROCFS_TMPFS[@]}"; do
    docker exec "$syscont_name" bash -c "mount | grep $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "tmpfs on $mnt_path/$node type tmpfs (ro,relatime" ]]
  done

  true
}

# verifies the given inner container path contains a procfs mount backed by sysbox-fs
function verify_inner_cont_procfs_mnt() {

  # argument check
  ! [[ "$#" < 3 ]]

  local syscont_name=$1
  local inner_cont_name=$2
  local mnt_path=$3
  local priv=$4

  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name sh -c \"mount | grep \"proc on $mnt_path type proc \(rw\"\""
  [ "$status" -eq 0 ]

  for node in "${PROCFS_EMU[@]}"; do
    docker exec "$syscont_name" bash -c "docker exec $inner_cont_name sh -c \"mount | grep /proc/$node\""
    [ "$status" -eq 0 ]

    if [ -z "$priv" ] && [ "$node" == "sys" ]; then
      [[ "$output" =~ "sysboxfs on /proc/$node type fuse (ro" ]]
    else
      [[ "$output" =~ "sysboxfs on /proc/$node type fuse (rw" ]]
    fi
  done

  true
}
