#!/usr/bin/env bats

#
# Testing of common handler.
#

load ../helpers/run
load ../helpers/fs
load ../helpers/ns

disable_ipv6=/proc/sys/net/ipv6/conf/all/disable_ipv6

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
}

# lookup
@test "common handler: lookup" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # disable_ipv6
  sv_runc exec syscont sh -c "ls -l $disable_ipv6"
  [ "$status" -eq 0 ]

  verify_root_rw "$output"
  [ "$status" -eq 0 ]
}

@test "common handler: disable_ipv6" {

  local enable="0"
  local disable="1"

  host_orig_val=$(cat $disable_ipv6)

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # By default ipv6 should be enabled within a system container
  # launched by sysvisor-runc directly (e.g., without docker) Note
  # that in system container launched with docker + sysvisor-runc,
  # docker (somehow) disables ipv6.
  sv_runc exec syscont sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$enable" ]

  # Disable ipv6 in system container and verify
  sv_runc exec syscont sh -c "echo $disable > $disable_ipv6"
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$disable" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat $disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]

  # Re-enable ipv6 within system container
  sv_runc exec syscont sh -c "echo $enable > $disable_ipv6"
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$enable" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat $disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]
}

@test "common handler: /proc/sys hierarchy" {

  walk_proc="find /proc/sys -print"

  # launch sys container
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # get the list of dirs under /proc/sys
  sv_runc exec syscont sh -c "${walk_proc}"
  [ "$status" -eq 0 ]
  sc_proc_sys="$output"

  # unshare all ns and get the list of dirs under /proc/sys
  ns_proc_sys=$(unshare_all sh -c "${walk_proc}")

  # for now the expectation is that sysvisor-fs will expose the same
  # hierarchy under /proc/sys as linux does when unsharing all ns;
  # in the future this may change (e.g., when sysvisor-fs exposes
  # /proc/sys files that linux hides because the associated resources
  # aren't namespaced)
  [ "$sc_proc_sys" == "$ns_proc_sys" ]
}
