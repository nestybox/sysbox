#!/usr/bin/env bats

# General tests for sysbox-fs /proc mounts.
#
# Sysbox-fs handler-specific tests are under the proc<Handler>.bats file.

load ../helpers/fs
load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
}

@test "proc lookup" {

  #
  # Verify that portions of /proc inside a sys container backed by
  # sysbox-fs have the same attributes as /proc in the host.
  #

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  for file in $SYSFS_PROC; do
    want_perm=$(ls -ld $file | awk '{print $1}')
    want_bytes=$(ls -ld $file | awk '{print $2}')
    want_owner=$(ls -ld $file | awk '{print $3}')
    want_group=$(ls -ld $file | awk '{print $4}')

    sv_runc exec syscont sh -c "ls -ld $file"
    [ "$status" -eq 0 ]
    listing=$output

    got_perm=$(echo "${listing}" | awk '{print $1}')
    got_bytes=$(echo "${listing}" | awk '{print $2}')
    got_owner=$(echo "${listing}" | awk '{print $3}')
    got_group=$(echo "${listing}" | awk '{print $4}')

    [[ "$want_perm" == "$got_perm" ]]
    [[ "$want_bytes" == "$got_bytes" ]]
    [[ "$want_owner" == "$got_owner" ]]
    [[ "$want_group" == "$got_group" ]]
  done
}

@test "proc read-only" {

  #
  # Verify read-only files backed by sysbox-fs are truly read-only
  #

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  for file in $SYSFS_PROC; do
    sv_runc exec syscont sh -c "ls -ld $file"
    [ "$status" -eq 0 ]
    listing=$output

    perm=$(echo "${listing}" | awk '{print $1}')

    if [[ "$perm" == "-r--r--r--" ]]; then
       sv_runc exec syscont sh -c "echo \"data\" > $file"
       [ "$status" -eq 1 ]
       [[ "$output" =~ "Permission denied" ]]
    fi
  done
}
