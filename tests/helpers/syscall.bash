#!/bin/bash

#
# syscall emulation test helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

# List of files or dirs under procfs emulated bys sysbox-fs
procfs_emu=( "sys" "uptime" "swaps" )

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

  for node in "${procfs_emu[@]}"; do
    docker exec "$syscont_name" bash -c "mount | grep $mnt_path/$node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse $opt" ]]
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

  for node in "${procfs_emu[@]}"; do
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
