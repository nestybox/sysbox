#!/usr/bin/env bats

#
# Integration test to verify the sysbox-mgr subid allocator.
#

load ../helpers/run
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "uid alloc basic" {

  if [ -z "$SHIFT_ROOTFS_UIDS" ]; then
    skip "uid shifting disabled"
  fi

  num_syscont=5

  declare -a syscont_name
  declare -a syscont_uids
  declare -a syscont_gids

  # ensure the subuid(gid) ranges look good
  uid_size=$(grep sysbox /etc/subuid | cut -d":" -f3)
  gid_size=$(grep sysbox /etc/subgid | cut -d":" -f3)

  [ "$uid_size" -eq 65536 ]
  [ "$gid_size" -eq 65536 ]

  # start multiple sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" ${CTR_IMG_REPO}/alpine:latest tail -f /dev/null)
  done

  # verify all sys containers got the uid(gid) range of 64k each
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/uid_map"
    [ "$status" -eq 0 ]
    map="$output"

    uid=$(echo "$map" | awk '{print $2}')
    uid_size=$(echo "$map" | awk '{print $3}')
    [ $uid_size -ge 65536 ]

    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/gid_map"
    [ "$status" -eq 0 ]
    map="$output"

    gid=$(echo "$map" | awk '{print $2}')
    gid_size=$(echo "$map" | awk '{print $3}')
    [ $gid_size -ge 65536 ]

    for id in ${syscont_uids[@]}; do
      [ $id -eq $uid ]
    done

    for id in ${syscont_gids[@]}; do
      [ $id -eq $gid ]
    done

    syscont_uids[$i]=$uid
    syscont_gids[$i]=$gid
  done

  # stop the sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done
}
