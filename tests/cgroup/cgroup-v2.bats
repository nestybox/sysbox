#!/usr/bin/env bats

#
# Tests that verify cgroups v2 contraints and delegation on system containers.
#
# The tests verify that a sys container is limited by the cgroups assigned to it
# at creation time, and these limits can't be bypassed from within the container.
#
# The tests also verify that a cgroup manager inside the sys container (e.g., systemd)
# can create cgroups inside the sys container and assign resources. Such assignments
# are implicitly constrained by the resources assigned to the sys container itself.
#

load ../helpers/run
load ../helpers/fs
load ../helpers/docker
load ../helpers/cgroups
load ../helpers/systemd
load ../helpers/sysbox-health
load cgv2-common

function teardown() {
  sysbox_log_check
}

@test "cgroup v2: cpuset" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if systemd_env; then
		skip "systemd detected"
	fi

	test_cgroup_cpuset
}

@test "cgroup v2: cpus" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if systemd_env; then
		skip "systemd detected"
	fi

	test_cgroup_cpus
}

@test "cgroup v2: memory" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	# NOTE: enable swap on Ubuntu / Debian by adding this to /etc/default/grub:
	#
	# GRUB_CMD_LINE_LINUX="systemd.unified_cgroup_hierarchy=1 cgroup_enable=memory swapaccount=1"
	#
	# Then `sudo update-grub` and reboot.
	#
	# For RPM based distros, memory swap is enabled by default. See here for more:
	# https://docs.docker.com/engine/install/linux-postinstall/#your-kernel-does-not-support-cgroup-swap-limit-capabilities

	if [ ! -f "/sys/fs/cgroup/memory.swap.max" ]; then
		skip "requires host with memory swap limit support"
	fi

	if systemd_env; then
		skip "systemd detected"
	fi

	test_cgroup_memory
}

@test "cgroup v2: permissions" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if systemd_env; then
		skip "systemd detected"
	fi

	test_cgroup_perm
}

@test "cgroup v2: delegation" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if systemd_env; then
		skip "systemd detected"
	fi

	test_cgroup_delegation
}

#
# cgroup v2 systemd tests
#

@test "cgroup v2 systemd: enable docker systemd driver" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	docker-cfg -v --cgroup-driver=systemd
}

@test "cgroup v2 systemd: cpuset" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_cpuset
}

@test "cgroup v2 systemd: cpus" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_cpus
}

@test "cgroup v2 systemd: memory" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if [ ! -f "/sys/fs/cgroup/memory.swap.max" ]; then
		skip "requires host with memory swap limit support"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_memory
}

@test "cgroup v2 systemd: permissions" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_perm
}

@test "cgroup v2 systemd: delegation" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_delegation
}

@test "cgroup v2 systemd: disable docker systemd driver" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	docker-cfg --cgroup-driver=cgroupfs
}

# Verify all is good with the revert back to the Docker cgroupfs driver
@test "cgroup v2: revert" {
	if ! host_is_cgroup_v2; then
		skip "requires host in cgroup v2"
	fi

	test_cgroup_cpus
}
