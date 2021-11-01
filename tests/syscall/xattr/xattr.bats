#!/usr/bin/env bats

#
# Verify trapping & emulation on "setxattr"
#

load ../../helpers/run
load ../../helpers/syscall
load ../../helpers/docker
load ../../helpers/environment
load ../../helpers/mounts
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "*xattr" {

	mkdir /mnt/scratch/test
	chown 165536:165536 /mnt/scratch/test

	# deploy a sys container
	local syscont=$(docker_run --rm -v /mnt/scratch/test:/mnt ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# the attr package brings the setfattr and getfattr utils
	docker exec "$syscont" sh -c "apk add attr"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mkdir /mnt/tdir && touch /mnt/tdir/tfile"
	[ "$status" -eq 0 ]

	# set some xattrs
	docker exec "$syscont" sh -c 'setfattr -n trusted.overlay.opaque -v "y" /mnt/tdir/tfile'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'setfattr -n trusted.another -v "another value" /mnt/tdir/tfile'
	[ "$status" -eq 1 ]

	docker exec "$syscont" sh -c 'setfattr -n user.x -v "user value" /mnt/tdir/tfile'
	[ "$status" -eq 0 ]

	# getfattr -d will invoke the listxattr() syscall
	docker exec "$syscont" sh -c 'cd /mnt && getfattr -d -m "trusted\." tdir/tfile'
	[ "$status" -eq 0 ]
	[[ "$output" =~ "trusted.overlay.opaque=\"y\"" ]]

	# getfattr -n will invoke the getaxattr() syscall
	docker exec "$syscont" sh -c 'cd /mnt && getfattr -n "trusted\.another" tdir/tfile'
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not supported" ]]

	docker exec "$syscont" sh -c 'getfattr -d /mnt/tdir/tfile'
	[ "$status" -eq 0 ]
	[[ "$output" =~ "user.x=\"user value\"" ]]

	# let's try again as a non-root user; the trusted.* xattr should be hidden
	docker exec -u 1000:1000 "$syscont" sh -c 'cd /mnt/tdir && getfattr -d -m "trusted\." tfile'
	[ "$status" -eq 0 ]
	[[ "$output" =~ "" ]]

	docker exec -u 1000:1000 "$syscont" sh -c 'cd /mnt/tdir && getfattr -d tfile'
	[ "$status" -eq 0 ]
	[[ "$output" =~ "user.x=\"user value\"" ]]

	# remove the trusted.overlay.opaque attribute; the "cd" is used on purpose to
	# check that sysbox-fs resolves non-absolute paths correctly
	docker exec "$syscont" sh -c 'cd /mnt && setfattr -x trusted.overlay.opaque tdir/tfile'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'getfattr -n "trusted.overlay.opaque" tdir/tfile 2>/dev/null'
	[ "$status" -eq 1 ]

	docker_stop "$syscont"

	rm -rf /mnt/scratch/test
}

@test "f*xattr & l*xattr" {

	# build the xattr-test binary (tests the f*xattr and l*xattr syscalls)
	pushd tests/syscall/xattr
	make xattr-test
	popd

	mkdir /mnt/scratch/test
	chown 165536:165536 /mnt/scratch/test

	# deploy a sys container
	local syscont=$(docker_run --rm -v /mnt/scratch/test:/mnt ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# create a test file inside the container
	docker exec "$syscont" sh -c "mkdir /mnt/tdir && touch /mnt/tdir/tfile"
	[ "$status" -eq 0 ]

	# copy the xattr-test file into the container
	docker cp tests/syscall/xattr/xattr-test $syscont:/bin/xattr-test

	# run the test
	docker exec "$syscont" sh -c "xattr-test /mnt/tdir/tfile"
	[ "$status" -eq 0 ]

	docker_stop "$syscont"
	rm -rf /mnt/scratch/test
}

@test "xattr: trusted.overlay.opaque" {

	mkdir /mnt/scratch/test
	chown 165536:165536 /mnt/scratch/test

	# deploy a sys container
	local syscont=$(docker_run --rm -v /mnt/scratch/test:/mnt ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# the attr package brings the setfattr and getfattr utils
	docker exec "$syscont" sh -c "apk add attr"
	[ "$status" -eq 0 ]

	# setup the overlayfs lower, upper, work, and merged dirs (but don't mount yet).
	docker exec "$syscont" sh -c "mkdir /mnt/lower && mkdir /mnt/upper && mkdir /mnt/work && mkdir /mnt/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mkdir /mnt/lower/ld1 && touch /mnt/lower/ld1/l1"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mkdir /mnt/upper/ld1"
	[ "$status" -eq 0 ]

	# adding trusted.overlay.opaque to /mnt/upper/ld1 hides the contents of the lower ld1
	docker exec "$syscont" sh -c 'setfattr -n trusted.overlay.opaque -v "y" /mnt/upper/ld1'
	[ "$status" -eq 0 ]

	# the "cd" is used on purpose to check that sysbox-fs resolves non-absolute paths correctly
	docker exec "$syscont" sh -c 'cd /mnt/upper && getfattr -n "trusted.overlay.opaque" ld1 2>/dev/null'
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" =~ 'trusted.overlay.opaque="y"' ]]

	# create the overlayfs mount and verify the opaque attribute took effect (/mnt/merged/ld1/l1 should be hidden).
	docker exec "$syscont" sh -c "mount -t overlay overlay -olowerdir=/mnt/lower,upperdir=/mnt/upper,workdir=/mnt/work /mnt/merged"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "ls /mnt/merged/ld1"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	# umount overlayfs
	docker exec "$syscont" sh -c "umount /mnt/merged"
	[ "$status" -eq 0 ]

	# remove the trusted.overlay.opaque attribute; the "cd" is used on purpose to
	# check that sysbox-fs resolves non-absolute paths correctly
	docker exec "$syscont" sh -c 'cd /mnt && setfattr -x trusted.overlay.opaque upper/ld1'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'getfattr -n "trusted.overlay.opaque" /mnt/upper/ld1 2>/dev/null'
	[ "$status" -eq 1 ]

	# re-create the overlayfs mount
	docker exec "$syscont" sh -c "mount -t overlay overlay -olowerdir=/mnt/lower,upperdir=/mnt/upper,workdir=/mnt/work /mnt/merged"
	[ "$status" -eq 0 ]

	# /mnt/merged/ld1/l1 should now be visible
	docker exec "$syscont" sh -c "ls /mnt/merged/ld1"
	[ "$status" -eq 0 ]
	[[ "$output" == "l1" ]]

	# umount overlayfs
	docker exec "$syscont" sh -c "umount /mnt/merged"
	[ "$status" -eq 0 ]

	docker_stop "$syscont"

	rm -rf /mnt/scratch/test
}

@test "l*xattr high-util: nixos use-case" {

	# Deploy a sys container with nixos tooling pre-installed.
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-nixos:latest tail -f /dev/null)

	# Verify that 'ripgrep' app is properly installed -- usually takes ~ 1.5 mins.
	docker exec "$syscont" bash -c "source ~/.nix-profile/etc/profile.d/nix.sh && nix-env -i ripgrep"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "created 39 symlinks in user environment" ]]

	docker_stop "$syscont"
}