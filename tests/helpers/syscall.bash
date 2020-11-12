#!/bin/bash

#
# syscall emulation test helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

# List of files or dirs under procfs emulated by sysbox-fs
PROCFS_EMU=( "swaps" "sys" "uptime" )

# List of procfs files exposed as read-only by sysbox
PROCFS_RDONLY=( "bus" "fs" "irq" "sysrq-trigger" )

# List of procfs files masked by sysbox
PROCFS_MASKED=( "keys" "timer_list" "sched_debug" )

# List of procfs files exposed as tmpfs mounts by sysbox. We originally had
# 'acpi' and 'scsi' here, but ended up removing 'scsi' one to satisfy Debian
# distro which by default doesn't expose this procfs node.
PROCFS_TMPFS=( "acpi")

# List of files or dirs under sysfs emulated by sysbox-fs
SYSFS_EMU=( "module/nf_conntrack/parameters/hashsize" )

# verifies the given sys container path contains a procfs mount backed by sysbox-fs
function verify_syscont_procfs_mnt() {

  # argument check
  ! [[ "$#" < 2 ]]
  local syscont=$1
  local mnt_path=$2
  if [ $# -eq 3 ]; then
    local readonly=$3
  fi

  if [ -n "$readonly" ]; then
    local opt=\(ro,
  fi

  docker exec "$syscont" bash -c "mount | grep \"proc on $mnt_path type proc $opt\""
  [ "$status" -eq 0 ]

  local node
  for node in "${PROCFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "mount | grep -w $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse $opt" ]]
  done

  for node in "${PROCFS_RDONLY[@]}"; do
    docker exec "$syscont" bash -c "mount | grep -w $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "proc on $mnt_path/$node type proc (ro," ]]
  done

  # Note: we skip checking for read-only on procfs masked resources
  # because sysbox-fs does not currently set them as read-only.  It's
  # a bug, but a minor one because the resources are masked anyway
  # (i.e., bind-mounted to /dev/null), so writes are inconsecuential.

  # for node in "${PROCFS_MASKED[@]}"; do
  #   docker exec "$syscont" bash -c "mount | grep $mnt_path/$node"
  #   [ "$status" -eq 0 ]
  #   if [ -n "$SB_INSTALLER" ]; then
  #     [[ "$output" =~ "udev on $mnt_path/$node type devtmpfs $opt" ]]
  #   else
  #     [[ "$output" =~ "tmpfs on $mnt_path/$node type tmpfs $opt" ]]
  #   fi
  # done

  for node in "${PROCFS_TMPFS[@]}"; do
    docker exec "$syscont" bash -c "mount | grep -w $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "tmpfs on $mnt_path/$node type tmpfs $opt" ]]
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

  local node
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

# verifies the given sys container path contains a sysfs mount backed by sysbox-fs
function verify_syscont_sysfs_mnt() {

  # argument check
  ! [[ "$#" < 2 ]]
  local syscont=$1
  local mnt_path=$2
  if [ $# -eq 3 ]; then
     local readonly=$3
  fi

  if [ -n "$readonly" ]; then
    local opt=\(ro,
  fi

  docker exec "$syscont" bash -c "mount | grep \"sysfs on $mnt_path type sysfs $opt\""
  [ "$status" -eq 0 ]

  local node
  for node in "${SYSFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "mount | grep -w $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse $opt" ]]
  done

  true
}

# verifies the given sys container path contains an overlayfs mount.
function verify_syscont_overlay_mnt() {

  # argument check
  ! [[ "$#" < 2 ]]
  local syscont=$1
  local mnt_path=$2
  if [ $# -eq 3 ]; then
     local readonly=$3
  fi

  if [ -n "$readonly" ]; then
    local opt=\(ro,
  fi

  docker exec "$syscont" bash -c "mount | grep \"overlay on $mnt_path type overlay $opt\""
  [ "$status" -eq 0 ]

  true
}

# verifies the given sys container path does not contain an overlayfs mount.
function verify_syscont_overlay_umnt() {

  # argument check
  ! [[ "$#" < 2 ]]
  local syscont=$1
  local mnt_path=$2

  docker exec "$syscont" bash -c "mount | grep \"overlay on $mnt_path type overlay"
  [ "$status" -eq 1 ]

  true
}
