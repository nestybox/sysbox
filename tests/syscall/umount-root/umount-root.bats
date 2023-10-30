#!/usr/bin/env bats

#
# Verify the root of a Sysbox container can never be unmounted, even
# if Sysbox is configured with "--allow-immutable-unmounts=true".
#

load ../../helpers/run
load ../../helpers/syscall
load ../../helpers/docker
load ../../helpers/sysbox
load ../../helpers/environment

function umount_root_test() {
	local withUnshare=$1

	local subuid=$(sysbox_get_subuid_range_start)

	# deploy a sys container
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# copy the umount-root-binary into the container
	#
	# XXX: for some reason "docker cp" fails to copy to /bin/. Not sure why since
	# there is nothing special about that dir (no mounts on it, no symlinks,
	# etc.) To work-around this, we copy to the container's "/" and then move it
	# to "/bin/."

	docker cp tests/syscall/umount-root/umount-root-test $syscont:/umount-root-test
	[ "$status" -eq 0 ]

	docker exec "$syscont" bash -c "mv /umount-root-test /bin/."
	[ "$status" -eq 0 ]

	# run the test
	if [[ "$withUnshare" == "true" ]]; then
		docker exec "$syscont" sh -c "unshare -m umount-root-test"
	else
		docker exec "$syscont" sh -c "umount-root-test"
	fi
	[ "$status" -eq 0 ]

	docker_stop "$syscont"
}

@test "umount-root prep" {
	# build the umount-root-test binary
	pushd tests/syscall/umount-root
	make umount-root-test
	popd
}

@test "umount-root" {
	umount_root_test false
}

@test "umount-root in new mount ns" {
	umount_root_test true
}

@test "config sysbox allow-immutable-unmounts=false" {
	sysbox_stop
	sysbox_start -t --allow-immutable-unmounts=false
}

@test "umount-root" {
	umount_root_test false
}

@test "umount-root in new mount ns" {
	umount_root_test true
}

@test "config sysbox to default" {
	sysbox_stop
	sysbox_start -t
}

@test "umount-root cleanup" {
	pushd tests/syscall/umount-root
	make clean
	popd
}
