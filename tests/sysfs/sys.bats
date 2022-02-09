#!/usr/bin/env bats

# General tests of /sys mount

load ../helpers/run
load ../helpers/ns
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Verify that /sys controls for non-namespaced kernel resources
# can't be modified from within a sys container.
@test "/sys non-namespaced resources" {

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
