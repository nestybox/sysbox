#!/usr/bin/env bats

# General tests of /sys mount

load ../helpers/run
load ../helpers/ns
load ../helpers/sysbox-health

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Verify that /sys controls for namespaced kernel resources
# can be modified from within a sys container and have proper
# container-to-host and container-to-container isolation.
@test "/sys namespaced resources" {

  # launch two sys containers (launch the 2nd one with docker to avoid
  # conflict with test setup/teardown functions)

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sc2=$(docker_run --rm alpine:3.10 tail -f /dev/null)

  # For each /sys control associated with a namespaced resource,
  # modify the value in the sys container and check isolation. Then
  # revert the value in the sys container and re-check.

  for entry in "${SYS_NS[@]}"; do
    eval $entry
    file=${e[0]}
    type=${e[1]}

    # read original values in host and in the sys containers

    host_orig=$(cat "$file")

    sv_runc exec syscont sh -c "cat $file"
    [ "$status" -eq 0 ]
    sc_orig="$output"

    docker exec "$sc2" sh -c "cat $file"
    [ "$status" -eq 0 ]
    sc2_orig="$output"

    # modify value in sys-cont1 (change depends on value type)

    case "$type" in
      BOOL)
        sc_new=$((! $sc_orig))
        ;;

      INT)
        sc_new=$(($sc_orig - 1))
        ;;
    esac

    sv_runc exec syscont sh -c "echo $sc_new > $file"
    [ "$status" -eq 0 ]

    sv_runc exec syscont sh -c "cat $file"
    [ "$status" -eq 0 ]
    [ "$output" == "$sc_new" ]

    # check for proper isolation

    host_val=$(cat "$file")
    [ "$host_val" == "$host_orig" ]

    docker exec "$sc2" sh -c "cat $file"
    [ "$status" -eq 0 ]
    [ "$output" == "$sc2_orig" ]

    # revert value in sys cont

    sv_runc exec syscont sh -c "echo $sc_orig > $file"
    [ "$status" -eq 0 ]

    sv_runc exec syscont sh -c "cat $file"
    [ "$status" -eq 0 ]
    [ "$output" == "$sc_orig" ]

    # re-check isolation

    host_val=$(cat "$file")
    [ "$host_val" == "$host_orig" ]

    docker exec "$sc2" sh -c "cat $file"
    [ "$status" -eq 0 ]
    [ "$output" == "$sc2_orig" ]

  done

  docker_stop "$sc2"
}

# Verify that /sys controls for non-namespaced kernel resources
# can't be modified from within a sys container.
@test "/sys non-namespaced resources" {
skip
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # For each /sys control associated with a non-namespaced resource,
  # verify that it's not possible to modify its value.

  for entry in "${SYS_NON_NS[@]}"; do
    eval $entry
    file=${e[0]}
    type=${e[1]}

    sv_runc exec syscont sh -c "cat $file"
    [ "$status" -eq 0 ]
    sc_orig="$output"

    case "$type" in
      BOOL)
        sc_new=$((! $sc_orig))
        ;;
      INT)
        sc_new=$(($sc_orig - 1))
        ;;
    esac

    sv_runc exec syscont sh -c "echo $sc_new > $file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Permission denied" ]]
  done
}

# verify sysfs can be remounted inside a sys container
@test "sysfs remount" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "mkdir /root/sys && mount -t sysfs sysfs /root/sys"
  [ "$status" -eq 0 ]

  # verify remounting does not allow access to non-namespaced resources
  local non_ns=('e=(/root/sys/kernel/profiling BOOL) '\
                'e=(/root/sys/kernel/rcu_normal BOOL) '\
                'e=(/root/sys/kernel/rcu_expedited BOOL) '\
                'e=(/root/sys/module/kernel/parameters/panic BOOL)')

  for entry in "${non_ns[@]}"; do
    eval $entry
    file=${e[0]}
    type=${e[1]}

    sv_runc exec syscont sh -c "cat $file"
    [ "$status" -eq 0 ]
    sc_orig="$output"

    case "$type" in
      BOOL)
        sc_new=$((! $sc_orig))
        ;;
      INT)
        sc_new=$(($sc_orig - 1))
        ;;
    esac

    sv_runc exec syscont sh -c "echo $sc_new > $file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Permission denied" ]]
  done
}
