#!/usr/bin/env bats

#
# Verify proper operation of a systemd within a sysbox container.
#

load ../../helpers/run
load ../../helpers/docker
load ../../helpers/sysbox-health
load ../../helpers/environment
load ../../helpers/systemd

function teardown() {
	sysbox_log_check
}

function check_systemd_mounts() {
	#
	# Check that the following resources are properly mounted to satisfy systemd
	# requirements:
	#
	# - /run                tmpfs   tmpfs    rw
	# - /run/lock           tmpfs   tmpfs    rw
	#
	local syscont=$1
	docker exec "$syscont" sh -c \
          "findmnt | egrep -e \"\/run .*tmpfs.*rw\" \
                   -e \"\/run\/lock .*tmpfs.*rw\" \
                   | wc -l | egrep -q 2"

	[ "$status" -eq 0 ]
}

@test "systemd ubuntu bionic" {

  # Ubuntu Bionic carries a version of Docker that needs cgroups v1
  if host_is_cgroup_v2; then
		skip "requires host in cgroup v1"
  fi

  # Launch systemd container.
  syscont=$(docker_run -d --rm --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd ${CTR_IMG_REPO}/ubuntu-bionic-systemd)

  wait_for_systemd_init $syscont

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$syscont" sh -c 'systemctl status | egrep "^ +State:"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "State: running" ]]

  # Verify that systemd's required resources are properly mounted.
  check_systemd_mounts $syscont

  # Verify that the hostname was properly set during container initialization,
  # which would confirm that 'hostnamectl' feature and its systemd dependencies
  # (i.e. dbus) are working as expected.
  docker exec "$syscont" sh -c \
         "hostnamectl | egrep -q \"hostname: sys-cont-systemd\""
  [ "$status" -eq 0 ]

  # verify virtualization type
  docker exec "$syscont" systemd-detect-virt
  [ "$status" -eq 0 ]
  [[ "$output" == "container-other" ]]

  # Restart a systemd service (journald) and verify it returns to 'running'
  # state.
  docker exec "$syscont" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" systemctl restart systemd-journald.service
  [ "$status" -eq 0 ]

  sleep 2

  docker exec "$syscont" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  # Cleanup
  docker_stop "$syscont"
  [ "$status" -eq 0 ]
}

@test "systemd ubuntu focal" {

  # In ubuntu focal, systemd-resolved requires /proc/kcore to be
  # exposed inside the container (i.e., not masked with a /dev/null
  # bind mount), otherwise systemd fails to initialize.

  # Launch systemd container.
  syscont=$(docker_run -d --rm --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd ${CTR_IMG_REPO}/ubuntu-focal-systemd)

  wait_for_systemd_init $syscont

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$syscont" sh -c 'systemctl status | egrep "^ +State:"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "State: running" ]]

  # Verify that systemd's required resources are properly mounted.
  check_systemd_mounts $syscont

  # Verify that the hostname was properly set during container initialization,
  # which would confirm that 'hostnamectl' feature and its systemd dependencies
  # (i.e. dbus) are working as expected.
  docker exec "$syscont" sh -c \
         "hostnamectl | egrep -q \"hostname: sys-cont-systemd\""
  [ "$status" -eq 0 ]

  # verify virtualization type
  docker exec "$syscont" systemd-detect-virt
  [ "$status" -eq 0 ]
  [[ "$output" == "container-other" ]]

  # Restart a systemd service (journald) and verify it returns to 'running'
  # state.
  docker exec "$syscont" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" systemctl restart systemd-journald.service
  [ "$status" -eq 0 ]

  sleep 2

  docker exec "$syscont" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  # Cleanup
  docker_stop "$syscont"
  [ "$status" -eq 0 ]
}

@test "systemd archlinux" {
  skip "testcase consistently failing in latest archlinux distros with systemd services' init errors"

  if [[ $(get_platform) != "amd64" ]]; then
     skip "archlinux supported only in amd64 architecture"
  fi

  local cur_kernel=$(get_kernel_release_semver)
  version_compare ${cur_kernel} "5.19.0" && :
  if [[ $? -eq 2 ]]; then
     skip "systemd takes > 1 min to boot on kernel < 5.19"
  fi

  # Launch systemd container.
  syscont=$(docker_run -d --rm --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd ${CTR_IMG_REPO}/archlinux-systemd)

  wait_for_systemd_init $syscont

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$syscont" sh -c 'systemctl status | egrep "^ +State:"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "State: running" ]]

  # Verify that systemd's required resources are properly mounted.
  check_systemd_mounts $syscont

  # Verify that the hostname was properly set during container initialization,
  # which would confirm that 'hostnamectl' feature and its systemd dependencies
  # (i.e. dbus) are working as expected.
  docker exec "$syscont" sh -c \
         "hostnamectl | egrep -q \"hostname: sys-cont-systemd\""
  [ "$status" -eq 0 ]

  # verify virtualization type
  docker exec "$syscont" systemd-detect-virt
  [ "$status" -eq 0 ]
  [[ "$output" == "container-other" ]]

  # Restart a systemd service (journald) and verify it returns to 'running'
  # state.
  docker exec "$syscont" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" systemctl restart systemd-journald.service
  [ "$status" -eq 0 ]

  sleep 2

  docker exec "$syscont" sh -c \
         "systemctl status systemd-journald.service | egrep \"active \(running\)\""
  [ "$status" -eq 0 ]

  # Cleanup
  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  docker image rm ${CTR_IMG_REPO}/archlinux-systemd
}

@test "systemd mount conflicts" {

  # For sys containers with systemd inside, sysbox mounts tmpfs over
  # certain directories of the container (this is a systemd
  # requirement). If the spec has conflicting mounts that are
  # non-tmpfs, these are ignored. If the conflicting spec mounts are
  # tmpfs, they are honored (see next test).

  docker volume create testVol
  [ "$status" -eq 0 ]

  # Launch systemd container.
  syscont=$(docker_run -d --rm \
                            --mount source=testVol,destination=/run \
                            --mount source=testVol,destination=/run/lock \
                            --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd ${CTR_IMG_REPO}/ubuntu-focal-systemd)

  wait_for_systemd_init $syscont

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$syscont" sh -c 'systemctl status | egrep "^ +State:"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "State: running" ]]

  # Verify that mount overlaps have been identified and replaced as per systemd
  # demands.
  check_systemd_mounts $syscont

  # Cleanup
  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  docker volume rm testVol
}

@test "systemd mount overrides" {

  # For sys containers with systemd inside, sysbox mounts tmpfs over certain directories
  # of the container (this is a systemd requirement). However, if the container spec
  # already has tmpfs mounts over any of these directories, we honor the spec mounts.

  docker volume create testVol
  [ "$status" -eq 0 ]

  # Launch systemd container.
  syscont=$(docker_run -d --rm \
                            --tmpfs /run:rw,noexec,nosuid,size=256m \
                            --tmpfs /run/lock:rw,noexec,nosuid,size=8m \
                            --name=sys-cont-systemd \
                            ${CTR_IMG_REPO}/ubuntu-focal-systemd-docker)

  wait_for_systemd_init $syscont

  # Verify that systemd has been properly initialized (no major errors observed).
  docker exec "$syscont" sh -c 'systemctl status | egrep "^ +State:"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "State: running" ]]

  # Verify that mount overrides have been honored. We are looking for
  # something like this inside the container:
  #
  # |-/run           tmpfs   tmpfs    rw,nosuid,nodev,noexec,relatime,size=262144k,uid=268666528,gid=268666528
  # | `-/run/lock    tmpfs   tmpfs    rw,nosuid,nodev,noexec,relatime,size=8192k,uid=268666528,gid=268666528

  docker exec "$syscont" sh -c "findmnt | egrep -e \"\/run .*tmpfs.*rw.*size=262144k\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "findmnt | egrep -e \"\/run\/lock .*tmpfs.*rw.*size=8192k\""
  [ "$status" -eq 0 ]

  # Cleanup
  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  docker volume rm testVol
}

@test "systemd /proc exposure" {

  # Verify that /proc nodes that we expose for systemd (/proc/kcore,
  # /proc/kallsyms, /proc/kmsg) do not present a security hole.

  syscont=$(docker_run -d --rm --name=sys-cont-systemd \
                            --hostname=sys-cont-systemd ${CTR_IMG_REPO}/ubuntu-focal-systemd)

  wait_for_systemd_init $syscont

  docker exec "$syscont" sh -c 'systemctl status | egrep "^ +State:"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "State: running" ]]

  docker exec "$syscont" sh -c "cat /proc/kcore"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Permission denied" ]]

  docker exec "$syscont" sh -c "cat /proc/kmsg"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Permission denied" ]]

  docker exec "$syscont" sh -c "cat /proc/kallsyms | head -n 10 | cut -d ' ' -f1"
  [ "$status" -eq 0 ]

  for line in "${lines[@]}"; do
    [[ "$line" == "0000000000000000" ]]
  done

  # Cleanup
  docker_stop "$syscont"
  [ "$status" -eq 0 ]
}
