#!/usr/bin/env bats

#
# Test that check Sysbox's health
#
# Note: these are meant to be executed after other tests, to verify
# that all is good with Sysbox's health after said tests.
#

load ../helpers/sysbox-health

function setup() {
   local distro=$(get_distro)
   if [[ "$distro" == "fedora" ]]; then
      skip "lsof hangs in fedora test container."
   fi
}

@test "sysboxfs_health" {
  run sysboxfs_health_check
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}

@test "sysboxmgr_health" {
  run sysboxmgr_health_check
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}
