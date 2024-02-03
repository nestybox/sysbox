#!/usr/bin/env bats

#
# Basic security checks
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "CVE-2024-21626 (runc leaked fds)" {
	# Verify this CVE does not affect Sysbox (i.e., the following command should
	# always fail, for all /proc/self/fd/<num>); with runc <= v1.1.11 (vulnerable
	# to CVE 2024-21626), one of these would most likely work and show the host's
	# "/" contents from within the container!
	for num in $(seq 1 20); do
		docker run --runtime=sysbox-runc -w /proc/self/fd/${num} ${CTR_IMG_REPO}/alpine:latest ls -l ../../..
		[ "$status" -ne 0 ]
	done
}
