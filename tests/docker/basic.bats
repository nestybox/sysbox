#!/usr/bin/env bats

#
# Basic tests running sys containers with docker
#

load ../helpers/run
load ../helpers/docker
load ../helpers/environment
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "basic sys container" {
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" hostname syscont
  [ "$status" -eq 0 ]

  docker exec "$syscont" hostname
  [ "$status" -eq 0 ]
  [ "$output" = "syscont" ]

  docker_stop "$syscont"
}

@test "docker --init" {
  local syscont=$(docker_run --init --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" pstree
  [ "$status" -eq 0 ]
  [[ "$output" =~ "init---tail" ]]

  docker_stop "$syscont"
}

@test "docker --oom-score-adj" {

  # Sysbox sys containers have this oom adj range
  local oom_min_val=-999
  local oom_max_val=1000
  local syscont=""

  syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # Verify default docker oom value is 0
  docker exec "$syscont" cat /proc/1/oom_score_adj
  [ "$status" -eq 0 ]
  [[ "$output" == "0" ]]

  # Verify oom range
  docker exec "$syscont" echo $oom_min_val > /proc/self/oom_score_adj
  [ "$status" -eq 0 ]

  docker exec "$syscont" echo $oom_max_val > /proc/self/oom_score_adj
  [ "$status" -eq 0 ]

  docker_stop "$syscont"

  # Verify override of default oom value
  local custom_val=-1
  syscont=$(docker_run --rm --oom-score-adj=$custom_val ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" cat /proc/1/oom_score_adj
  [ "$status" -eq 0 ]
  [[ "$output" == "$custom_val" ]]

  docker_stop "$syscont"
}

@test "docker --read-only" {

	local syscont=$(docker_run --rm --read-only ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# Verify rootfs is read-only
	docker exec "$syscont" sh -c 'mount | grep "on / " | grep "ro,"'
	[ "$status" -eq 0 ]

	# Verify /sys is read-only
	docker exec "$syscont" sh -c 'mount | grep "on /sys " | grep "ro,"'
	[ "$status" -eq 0 ]

	# Verify mounts under /sys are read-only (except /sys/fs/cgroup itself which
	# is a tmpfs rw mount; note that all controllers underneath are read-only).
	docker exec "$syscont" sh -c 'mount | grep "on /sys/" | grep -v "on /sys/fs/cgroup "'
	[ "$status" -eq 0 ]

	for line in "${lines[@]}"; do
		echo "$line" | grep "ro,"
	done

	# Verify all sysbox special/implicit mounts are also read-only
	docker exec "$syscont" sh -c 'mount | grep "on /var/lib/docker" | grep "ro,"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "on /var/lib/kubelet" | grep "ro,"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "on /var/lib/rancher/k3s" | grep "ro,"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "on /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs" | grep "ro,"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "on /lib/modules" | grep "ro,"'
	[ "$status" -eq 0 ]

	# Verify mounts under /proc backed by sysbox-fs are read-only
	docker exec "$syscont" sh -c 'mount | grep "on /proc/" | grep "sysboxfs on"'
	[ "$status" -eq 0 ]

	for line in "${lines[@]}"; do

		# XXX: skip /proc/sys for now, as it's not getting remounted read-only for
		# some reason.
		if [[ "$line" =~ "/proc/sys" ]]; then
			continue
		fi

		echo "$line" | grep "ro,"
	done

	docker_stop "$syscont"
}

@test "docker pause & unpause" {

	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	docker exec "$syscont" sh -c "touch /root/test-file.txt"
	[ "$status" -eq 0 ]

	docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
	[ "$status" -eq 0 ]

	wait_for_inner_dockerd $syscont

	docker exec "$syscont" sh -c "docker pull ${CTR_IMG_REPO}/busybox"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "docker pull ${CTR_IMG_REPO}/alpine"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "docker image ls | tail -n +2 | wc -l"
	[ "$status" -eq 0 ]
	[ "$output" -eq 2 ]

        local backing_fs=$(get_sysbox_backing_fs)

	for i in $(seq 1 4); do
		docker pause "$syscont"
		[ "$status" -eq 0 ]

		docker unpause "$syscont"
		[ "$status" -eq 0 ]

		docker exec "$syscont" sh -c "docker image ls | tail -n +2 | wc -l"
		[ "$status" -eq 0 ]
		[ "$output" -eq 2 ]

		file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" /var/lib/docker/$backing_fs")
		file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" /var/lib/docker/$backing_fs")
		[ "$file_uid" -eq 0 ]
		[ "$file_gid" -eq 0 ]

		file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" /root/test-file.txt")
		file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" /root/test-file.txt")
		[ "$file_uid" -eq 0 ]
		[ "$file_gid" -eq 0 ]
	done

	docker_stop "$syscont"
	[ "$status" -eq 0 ]
}

@test "docker stop & restart" {

	local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	docker exec "$syscont" sh -c "touch /root/test-file.txt"
	[ "$status" -eq 0 ]

	docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
	[ "$status" -eq 0 ]

	wait_for_inner_dockerd $syscont

	docker exec "$syscont" sh -c "docker pull ${CTR_IMG_REPO}/busybox"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "docker pull ${CTR_IMG_REPO}/alpine"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "docker image ls | tail -n +2 | wc -l"
	[ "$status" -eq 0 ]
	[ "$output" -eq 2 ]

        local backing_fs=$(get_sysbox_backing_fs)

	for i in $(seq 1 4); do
		docker_stop "$syscont"
		[ "$status" -eq 0 ]

		docker start "$syscont"
		[ "$status" -eq 0 ]

		docker exec "$syscont" sh -c "rm -f /var/run/docker.pid"
		[ "$status" -eq 0 ]

		docker exec "$syscont" sh -c "rm -f /run/docker/containerd/containerd.pid"
		[ "$status" -eq 0 ]

		docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
		[ "$status" -eq 0 ]

		wait_for_inner_dockerd $syscont

		docker exec "$syscont" sh -c "docker image ls | tail -n +2 | wc -l"
		[ "$status" -eq 0 ]
		[ "$output" -eq 2 ]

		file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" /var/lib/docker/$backing_fs")
		file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" /var/lib/docker/$backing_fs")
		[ "$file_uid" -eq 0 ]
		[ "$file_gid" -eq 0 ]

		file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" /root/test-file.txt")
		file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" /root/test-file.txt")
		[ "$file_uid" -eq 0 ]
		[ "$file_gid" -eq 0 ]
	done

	docker_stop "$syscont"
	[ "$status" -eq 0 ]

	docker rm "$syscont"
}
