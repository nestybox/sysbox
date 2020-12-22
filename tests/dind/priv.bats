#!/usr/bin/env bats

#
# Tests running Docker privileged containers inside a system container
#
# NOTE: per sysbox issue 482, running privileged containers inside
# a sys container requires inner docker version must be >= 19.03.
#

load ../helpers/run
load ../helpers/syscall
load ../helpers/docker
load ../helpers/sysbox-health
load ../helpers/fs

function teardown() {
  sysbox_log_check
}

@test "dind privileged basic" {

  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont_name" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" sh -c "docker run --privileged --rm -d alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"grep -i cap /proc/self/status\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
  [[ "${lines[1]}" =~ "CapPrm:".+"0000003fffffffff" ]]
  [[ "${lines[2]}" =~ "CapEff:".+"0000003fffffffff" ]]
  [[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
  [[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

  verify_inner_cont_procfs_mnt $syscont_name $inner_cont_name /proc priv

  # Verify sysfs mount attributes are the expected ones. Notice that CentOS/Redhat
  # enable SELinux by default so expected mount attributes may vary (i.e. "seclabel"
  # super-block attribute may be present).
  if ! selinux_on; then
    docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"mount | grep sysfs\""
    [ "$status" -eq 0 ]
    [[ "$output" == "sysfs on /sys type sysfs (rw,nosuid,nodev,noexec,relatime)" ]]
  else
    docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"mount | grep sysfs\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sysfs on /sys type sysfs (rw,seclabel,nosuid,nodev,noexec,relatime)" ]]
  fi

  docker_stop "$syscont_name"
}

# Privileged container security (privileged with respect to sys container context only)
@test "dind privileged security" {

  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont_name" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" sh -c "docker run --privileged --rm -d alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  # For each procfs and sysfs file associated with a non-namespaced resource,
  # verify that it's not possible to modify its value

  local all_non_ns=( "${PROC_SYS_NON_NS[@]}" "${SYS_NON_NS[@]}" )

  for entry in "${all_non_ns[@]}"; do
    eval $entry
    file=${e[0]}
    type=${e[1]}

    docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"cat $file\""
    [ "$status" -eq 0 ]
    sc_orig="$output"

    case "$type" in
      BOOL)
        sc_new=$((! $sc_orig))
        ;;

      INT)
        sc_new=$(($sc_orig - 1))
        ;;
    esac

    docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"echo $sc_new > $file\""
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Permission denied" ]]
  done

  docker_stop "$syscont_name"
}

@test "dind privileged ubuntu-bionic" {

  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker:latest tail -f /dev/null)

  docker exec -d "$syscont_name" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" sh -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$syscont_name"
}

@test "dind privileged ubuntu-bionic" {

  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker:latest tail -f /dev/null)

  docker exec -d "$syscont_name" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" sh -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$syscont_name"
}

@test "dind privileged debian-stretch" {

  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/debian-stretch-docker:latest tail -f /dev/null)

  docker exec -d "$syscont_name" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" sh -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$syscont_name"
}

# Run docker inside a privileged container inside a sys container (!)
@test "dind privileged docker" {

  # launch sys cont
  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/debian-stretch-docker:latest tail -f /dev/null)

  docker exec -d "$syscont_name" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  # launch priv container inside sys cont
  docker exec "$syscont_name" sh -c "docker run --privileged --rm -d ${CTR_IMG_REPO}/alpine-docker:latest tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  docker exec -d "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"dockerd > /var/log/dockerd-log 2>&1\""
  [ "$status" -eq 0 ]

  sleep 3

  # launch container inside priv container inside sys cont
  docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"docker run --rm -d busybox tail -f /dev/null\""
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"docker ps --format \"{{.ID}}\"\""
  [ "$status" -eq 0 ]
  local inner_inner_cont_name="$output"

  docker exec "$syscont_name" sh -c "docker exec $inner_cont_name sh -c \"docker exec $inner_inner_cont_name sh -c \"busybox | head -1\"\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$syscont_name"
}

# TODO: write tests that verify docker storage & networking inside a priv container inside a sys container
