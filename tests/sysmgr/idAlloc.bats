#!/usr/bin/env bats

#
# Integration test to verify the sysbox-mgr subid allocator.
#

load ../helpers/run

@test "/etc/subuid check" {

  # verify sysbox-mgr --subid-range-size option works
  sv_mgr_stop
  sv_mgr_start "--subid-range-size 131072"
  uid_size=$(grep sysbox /etc/subuid | cut -d":" -f3)
  gid_size=$(grep sysbox /etc/subgid | cut -d":" -f3)
  [ "$uid_size" -eq 131072 ]
  [ "$gid_size" -eq 131072 ]

  # verify sysbox-mgr default config of /etc/subuid(gid)
  sv_mgr_stop
  sv_mgr_start
  uid_size=$(grep sysbox /etc/subuid | cut -d":" -f3)
  gid_size=$(grep sysbox /etc/subgid | cut -d":" -f3)
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
  uid_size=$(grep sysbox /etc/subuid | cut -d":" -f3)
  gid_size=$(grep sysbox /etc/subgid | cut -d":" -f3)

  [ "$uid_size" -ge $((65536 * "$num_syscont")) ]
  [ "$gid_size" -ge $((65536 * "$num_syscont")) ]

  # start multiple sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" alpine:latest tail -f /dev/null)
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
  sv_mgr_start "--subid-policy no-reuse --subid-range-size 131072"

  # start two sys containers
  declare -a syscont_name
  num_syscont=2

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" alpine:latest tail -f /dev/null)
  done

  # start 3rd sys container and verify this fails due to no uid availability
  # (don't use docker_run() as we want to get the $status and $output)
  docker run --runtime=sysbox-runc --rm -d alpine:latest tail -f /dev/null 2>&1
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
  sv_mgr_start "--subid-range-size 131072"

  # Start 4 sys containers; the first two should get new ids; the last
  # two should get re-used ids.
  declare -a syscont_name
  declare -a syscont_uids
  declare -a syscont_gids

  num_syscont=4

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" alpine:latest tail -f /dev/null)

    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/uid_map | awk '{print \$2}'"
    [ "$status" -eq 0 ]
    syscont_uids[$i]="$output"

    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/gid_map | awk '{print \$2}'"

    [ "$status" -eq 0 ]
    syscont_gids[$i]="$output"
  done

  # verify uid & gid match
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    [ ${syscont_uids[$i]} -eq ${syscont_gids[$i]} ]
  done

  # verify uid & gid for the first two containers are different
  [ ${syscont_uids[0]} -ne ${syscont_uids[1]} ]
  [ ${syscont_gids[0]} -ne ${syscont_gids[1]} ]

  # verify uid & gid for the first two and last two containers match
  [ ${syscont_uids[0]} -eq ${syscont_uids[2]} ] || [ ${syscont_uids[0]} -eq ${syscont_uids[3]} ]
  [ ${syscont_uids[1]} -eq ${syscont_uids[2]} ] || [ ${syscont_uids[1]} -eq ${syscont_uids[3]} ]
  [ ${syscont_gids[0]} -eq ${syscont_gids[2]} ] || [ ${syscont_gids[0]} -eq ${syscont_gids[3]} ]
  [ ${syscont_gids[1]} -eq ${syscont_gids[2]} ] || [ ${syscont_gids[1]} -eq ${syscont_gids[3]} ]

  # stop the sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done

  # cleanup
  sv_mgr_stop
  sv_mgr_start
}

@test "ident-map basic" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "uid shifting disabled"
  fi

  # restart sysbox-mgr in ident-map mode
  sv_mgr_stop
  sv_mgr_start "--subid-ident-map"

  # launch multiple sys containers and verify they have their uid(gid)s identity-mapped
  declare -a syscont_name
  num_syscont=4

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" nestybox/alpine-docker-dbg:latest tail -f /dev/null)

    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/uid_map | awk '{print \$1 \$2 \$3}'"
    [ "$status" -eq 0 ]
    [[ "$output" == "0065536" ]]

    docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/gid_map | awk '{print \$1 \$2 \$3}'"
    [ "$status" -eq 0 ]
    [[ "$output" == "0065536" ]]
  done

  # stop the sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done

  # restart sysbox-mgr in regular mode
  sv_mgr_stop
  sv_mgr_start
}

@test "ident-map dind" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "uid shifting disabled"
  fi

  # restart sysbox-mgr in ident-map mode
  sv_mgr_stop
  sv_mgr_start "--subid-ident-map"

  # launch multiple sys containers and verify they can run docker inside
  declare -a syscont_name
  num_syscont=2

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" nestybox/alpine-docker-dbg:latest tail -f /dev/null)
    docker exec "${syscont_name[$i]}" sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
    [ "$status" -eq 0 ]
  done

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker exec "${syscont_name[$i]}" sh -c "docker run hello-world"
    [ "$status" -eq 0 ]
  done

  # stop the sys containers
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done

  # restart sysbox-mgr in regular mode
  sv_mgr_stop
  sv_mgr_start
}
