#!/usr/bin/env bats

#
# Verify mounts using "/proc/self" paths inside a Sysbox container
#

load ../../../helpers/run
load ../../../helpers/docker

@test "proc-self-mount test prep" {
	# build the pivot-root-test binary
	pushd tests/syscall/mount/proc-self-mount
	make
	popd
}

@test "proc-self-mount test" {
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# copy the test binary into the container
	#
	# XXX: for some reason "docker cp" fails to copy to /bin/. Not sure why since
	# there is nothing special about that dir (no mounts on it, no symlinks,
	# etc.) To work-around this, we copy to the container's "/" and then move it
	# to "/bin/."
	docker cp tests/syscall/mount/proc-self-mount/proc-self-mount-test $syscont:/proc-self-mount-test
	[ "$status" -eq 0 ]

	docker exec "$syscont" bash -c "mv /proc-self-mount-test /bin/."
	[ "$status" -eq 0 ]

	# run the test
	docker exec "$syscont" sh -c "proc-self-mount-test"
	[ "$status" -eq 0 ]

	docker_stop "$syscont"
}

@test "proc-self-mount test cleanup" {
	pushd tests/syscall/mount/proc-self-mount
	make clean
	popd
}
