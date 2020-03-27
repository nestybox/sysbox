#!/usr/bin/env bats

#
# Test that check Sysbox's health
#
# Note: these are meant to be executed after other tests, to verify
# that all is good with Sysbox's health after said tests.
#

load ../helpers/sysbox-health

@test "sysboxfs_health" {
  sysboxfs_health_check
}

@test "sysboxmgr_health" {
  sysboxmgr_health_check
}
