#!/usr/bin/env bats

#
# Verify pivot-root inside a Sysbox container
#

load ../../helpers/run
load ../../helpers/syscall
load ../../helpers/docker
load ../../helpers/sysbox
load ../../helpers/environment

function pivot_root_test() {
	local withUnshare=$1

	local subuid=$(sysbox_get_subuid_range_start)

	# deploy a sys container
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# copy the pivot-root-binary into the container
	#
	# XXX: for some reason "docker cp" fails to copy to /bin/. Not sure why since
	# there is nothing special about that dir (no mounts on it, no symlinks,
	# etc.) To work-around this, we copy to the container's "/" and then move it
	# to "/bin/."

	docker cp tests/syscall/pivot-root/pivot-root-test $syscont:/pivot-root-test
	[ "$status" -eq 0 ]

	docker exec "$syscont" bash -c "mv /pivot-root-test /bin/."
	[ "$status" -eq 0 ]

	# run the test
	if [[ "$withUnshare" == "true" ]]; then
		docker exec "$syscont" sh -c "unshare -m pivot-root-test"
	else
		docker exec "$syscont" sh -c "pivot-root-test"
	fi
	[ "$status" -eq 0 ]

	docker_stop "$syscont"
}

@test "pivot-root prep" {
	# build the pivot-root-test binary
	pushd tests/syscall/pivot-root
	make pivot-root-test
	popd
}

@test "pivot-root" {
	pivot_root_test false
}

@test "pivot-root in new mount ns" {
	pivot_root_test true
}

@test "config sysbox allow-immutable-unmounts=false" {
	sysbox_stop
	sysbox_start -t --allow-immutable-unmounts=false
}

@test "pivot-root" {
	pivot_root_test false
}

@test "pivot-root in new mount ns" {
	pivot_root_test true
}

@test "config sysbox to default" {
	sysbox_stop
	sysbox_start -t
}

@test "pivot-root cleanup" {
	pushd tests/syscall/pivot-root
	make clean
	popd
}
