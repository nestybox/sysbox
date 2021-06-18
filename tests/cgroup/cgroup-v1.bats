#!/usr/bin/env bats

#
# Tests that verify cgroups v1 contraints and delegation on system containers.
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
load cgv1-common

function teardown() {
  sysbox_log_check
}

#
# cgroup v1 tests
#

@test "cgroup v1: cpuset" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	test_cgroup_cpuset
}

@test "cgroup v1: cpus" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	test_cgroup_cpus
}

@test "cgroup v1: memory" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	test_cgroup_memory
}

@test "cgroup v1: permissions" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	test_cgroup_perm
}

@test "cgroup v1: delegation" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	test_cgroup_delegation
}

#
# cgroup v1 systemd tests
#

@test "cgroup v1 systemd: enable docker systemd driver" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	docker-cfg -v --cgroup-driver=systemd
}

@test "cgroup v1 systemd: cpuset" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_cpuset
}

@test "cgroup v1 systemd: cpus" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_cpus
}

@test "cgroup v1 systemd: memory" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_memory
}

@test "cgroup v1 systemd: permissions" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_perm
}

@test "cgroup v1 systemd: delegation" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_delegation
}

@test "cgroup v1 systemd: disable docker systemd driver" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	if ! systemd_env; then
		skip "no systemd detected"
	fi

	docker-cfg --cgroup-driver=cgroupfs
}

# Verify all is good with the revert back to the Docker cgroupfs driver
@test "cgroup v1: revert" {
	if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
	fi

	test_cgroup_cpus
}
