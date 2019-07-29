#!/usr/bin/env bats

#
# Integration test to verify exclusive uid/gid allocation per sys container
#

load ../helpers/run

@test "/etc/subuid check" {

  # verify sysvisor-mgr --subid-range option works
  sv_mgr_stop
  sv_mgr_start --subid-range 131072
  uid_size=$(grep sysvisor /etc/subuid | cut -d":" -f3)
  gid_size=$(grep sysvisor /etc/subgid | cut -d":" -f3)
  [ "$uid_size" -eq 131072 ]
  [ "$gid_size" -eq 131072 ]

  # verify sysvisor-mgr default config of /etc/subuid(gid)
  sv_mgr_stop
  sv_mgr_start
  uid_size=$(grep sysvisor /etc/subuid | cut -d":" -f3)
  gid_size=$(grep sysvisor /etc/subgid | cut -d":" -f3)
  [ "$uid_size" -eq 268435456 ]
  [ "$gid_size" -eq 268435456 ]
}

@test "uid alloc basic" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "uid shifting disabled"
  fi

  num_syscont=5

  declare -a syscont_name
  declare -a syscont_uids
  declare -a syscont_gids

  # ensure the subuid(gid) ranges look good
  uid_size=$(grep sysvisor /etc/subuid | cut -d":" -f3)
  gid_size=$(grep sysvisor /etc/subgid | cut -d":" -f3)

  [ "$uid_size" -ge $((65536 * "$num_syscont")) ]
  [ "$gid_size" -ge $((65536 * "$num_syscont")) ]

  # start multiple sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" debian:latest tail -f /dev/null)
  done

  # verify each got an exclusive uid(gid) range of 64k each
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
      [ $id -ne $uid ]
    done

    for id in ${syscont_gids[@]}; do
      [ $id -ne $gid ]
    done

    syscont_uids[$i]=$uid
    syscont_gids[$i]=$gid
  done

  # stop the sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done
}

@test "uid exhaust" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "uid shifting disabled"
  fi

  sv_mgr_stop
  sv_mgr_start --subid-policy "no-reuse" --subid-range 131072

  # start two sys containers
  num_syscont=2

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" debian:latest tail -f /dev/null)
  done

  # start 3rd sys container and verify this fails due to no uid availability
  # (don't use docker_run() as we want to get the $status and $output)
  docker run --runtime=sysvisor-runc --rm -d debian:latest tail -f /dev/null 2>&1
  [ "$status" -eq 125 ]
  [[ "$output" =~ "subid allocation failed" ]]

  # stop the sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done

  # cleanup
  sv_mgr_stop
  sv_mgr_start
}

@test "uid reuse" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "uid shifting disabled"
  fi

  sv_mgr_stop
  sv_mgr_start --subid-range 131072

  # Start 4 sys containers; the first two should get new ids; the last
  # two should get re-used ids.
  num_syscont=4

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" debian:latest tail -f /dev/null)

    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/uid_map | awk '{print \$2}'"
    [ "$status" -eq 0 ]
    syscont_uids[$i]="$output"

    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/gid_map | awk '{print \$2}'"
    [ "$status" -eq 0 ]
    syscont_gids[$i]="$output"
  done

  # verify
  [ ${syscont_uids[0]} -eq ${syscont_uids[2]} ]
  [ ${syscont_uids[1]} -eq ${syscont_uids[3]} ]

  [ ${syscont_gids[0]} -eq ${syscont_gids[2]} ]
  [ ${syscont_gids[1]} -eq ${syscont_gids[3]} ]

  # stop the sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done

  # cleanup
  sv_mgr_stop
  sv_mgr_start
}
