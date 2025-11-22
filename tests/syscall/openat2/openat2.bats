#!/usr/bin/env bats

#
# Verify trapping & emulation of openat2 syscall
#

load ../../helpers/run
load ../../helpers/syscall
load ../../helpers/docker
load ../../helpers/environment
load ../../helpers/sysbox
load ../../helpers/sysbox-health

# Table of files to test openat2() within a sys container
# Format: "filesystem:filepath:expected_value"
# filesystem is either "/proc" or "/sys"
# If expected_value is empty, no comparison on the value is done
TEST_FILES=(
	# files not under a sysbox-fs mount
	# "/proc:partitions:"

	# files under a sysbox-fs mount (sysbox will trap openat2 on these)
	"/proc:uptime:"
	"/proc:swaps:"
	"/proc:sys/net/ipv4/ip_unprivileged_port_start:0"
	"/sys:kernel/profiling:"
)

function setup() {
	# build the openat2-test binary (tests the openat2 syscall)
	pushd tests/syscall/openat2
	make openat2-test
	popd

	cp tests/syscall/openat2/openat2-test /bin/.

	# deploy a sys container
	SYSCONT=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# copy the openat2-test file into the container
	#
	# XXX: for some reason "docker cp" fails to copy to /bin/. Not sure why since
	# there is nothing special about that dir (no mounts on it, no symlinks,
	# etc.) To work-around this, we copy to the container's "/" and then move it
	# to "/bin/."

	docker cp tests/syscall/openat2/openat2-test $SYSCONT:/openat2-test
	[ "$status" -eq 0 ]

	docker exec "$SYSCONT" bash -c "mv /openat2-test /bin/."
	[ "$status" -eq 0 ]
}

function teardown() {
	docker_stop "$SYSCONT"
	sysbox_log_check
}

@test "openat2 no flags" {
	for entry in "${TEST_FILES[@]}"; do
		IFS=':' read -r filesystem file expected <<< "$entry"
		echo "Testing openat2 with no flags on ${filesystem}/${file}"

		if [ -n "$expected" ]; then
			docker exec "$SYSCONT" sh -c "cd $filesystem && openat2-test -expected $expected $file"
		else
			docker exec "$SYSCONT" sh -c "cd $filesystem && openat2-test $file"
		fi
		[ "$status" -eq 0 ]
	done
}

@test "openat2 resolve flags" {
	# Sysbox drops some of the RESOLVE_* flags internally when opening /proc/sys files (since these are emulated by sysbox-fs via mounts on the container's procfs)
	for entry in "${TEST_FILES[@]}"; do
		IFS=':' read -r filesystem file expected <<< "$entry"
		echo "Testing openat2 with resolve flags on ${filesystem}/${file}"

		if [ -n "$expected" ]; then
			docker exec "$SYSCONT" sh -c "cd $filesystem && openat2-test -expected $expected -resolve 'RESOLVE_NO_SYMLINKS|RESOLVE_NO_XDEV|RESOLVE_NO_MAGICLINKS|RESOLVE_BENEATH' $file"
		else
			docker exec "$SYSCONT" sh -c "cd $filesystem && openat2-test -resolve 'RESOLVE_NO_SYMLINKS|RESOLVE_NO_XDEV|RESOLVE_NO_MAGICLINKS|RESOLVE_BENEATH' $file"
		fi
		[ "$status" -eq 0 ]
	done
}

@test "openat2 flags" {
	for entry in "${TEST_FILES[@]}"; do
		IFS=':' read -r filesystem file expected <<< "$entry"
		echo "Testing openat2 with flags on ${filesystem}/${file}"

		if [ -n "$expected" ]; then
			docker exec "$SYSCONT" sh -c "cd $filesystem && openat2-test -expected $expected -flags 'O_NOFOLLOW|O_CLOEXEC' $file"
		else
			docker exec "$SYSCONT" sh -c "cd $filesystem && openat2-test -flags 'O_NOFOLLOW|O_CLOEXEC' $file"
		fi
		[ "$status" -eq 0 ]
	done
}

@test "openat2 O_PATH flag" {
	# Sysbox drops the O_PATH flag internally when openat2 opens sysbox-fs emulated files under /proc and /sys (otherwise fd injection via SECCOMP_IOCTL_NOTIF_ADDFD fails)
	for entry in "${TEST_FILES[@]}"; do
		IFS=':' read -r filesystem file expected <<< "$entry"
		echo "Testing openat2 with O_PATH flag on ${filesystem}/${file}"

		# Note: O_PATH doesn't allow reading, so we don't use -expected here
		docker exec "$SYSCONT" sh -c "cd $filesystem && openat2-test -flags O_PATH $file"
		[ "$status" -eq 0 ]
	done
}




