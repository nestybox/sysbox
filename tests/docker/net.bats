#!/usr/bin/env bats

#
# Docker + Sysbox container networking tests
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "docker --net=host not allowed" {
	docker run --net=host -d --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null
	[ "$status" -ne 0 ]
}

@test "docker --net=container:<id>" {
	local sc1=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
	local sc2=$(docker_run --net=container:$sc1 ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# verify the containers share the same network and user namespaces
	sc1_pid=$(docker_cont_pid $sc1)
	sc2_pid=$(docker_cont_pid $sc2)

	sc1_netns=$(readlink /proc/${sc1_pid}/ns/net)
	sc2_netns=$(readlink /proc/${sc2_pid}/ns/net)

	sc1_userns=$(readlink /proc/${sc1_pid}/ns/user)
	sc2_userns=$(readlink /proc/${sc2_pid}/ns/user)

	[[ "$sc1_netns" == "$sc2_netns" ]]
	[[ "$sc1_userns" == "$sc2_userns" ]]

	# verify the other namespaces are not shared
	sc1_mntns=$(readlink /proc/${sc1_pid}/ns/mnt)
	sc2_mntns=$(readlink /proc/${sc2_pid}/ns/mnt)

	[[ "$sc1_mntns" != "$sc2_mntns" ]]

	# verify networking is ok
	docker exec $sc1 sh -c "apk update"
	[ "$status" -eq 0 ]

	docker exec $sc2 sh -c "apk update"
	[ "$status" -eq 0 ]

	# stop and restart the second container, verify it continues to share the
	# netns and userns with the first container and networking works fine.
	docker_stop $sc2
	[ "$status" -eq 0 ]

	docker start $sc2
	[ "$status" -eq 0 ]

	sc2_pid=$(docker_cont_pid $sc2)
	sc2_netns=$(readlink /proc/${sc2_pid}/ns/net)
	sc2_userns=$(readlink /proc/${sc2_pid}/ns/user)

	[[ "$sc1_netns" == "$sc2_netns" ]]
	[[ "$sc1_userns" == "$sc2_userns" ]]

	docker exec $sc2 sh -c "apk update"
	[ "$status" -eq 0 ]

	docker_stop $sc1
	docker_stop $sc2

	docker rm $sc1 $sc2
}
