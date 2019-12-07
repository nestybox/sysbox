#!/usr/bin/env bats

#
# Tests running Docker privileged containers inside a system container
#
# NOTE: per sysbox issue 482, running privileged containers inside
# a sys container requires inner docker version must be >= 19.03.
#

load ../helpers/run

SYSCONT_NAME=""

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "dind privileged basic" {

  SYSCONT_NAME=$(docker_run --rm nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run --privileged --rm -d alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"grep -i cap /proc/self/status\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
  [[ "${lines[1]}" =~ "CapPrm:".+"0000003fffffffff" ]]
  [[ "${lines[2]}" =~ "CapEff:".+"0000003fffffffff" ]]
  [[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
  [[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"mount | grep proc\""
  [ "$status" -eq 0 ]
  [[ "$output" == "proc on /proc type proc (rw,nosuid,nodev,noexec,relatime)" ]]

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"mount | grep sysfs\""
  [ "$status" -eq 0 ]
  [[ "$output" == "sysfs on /sys type sysfs (rw,nosuid,nodev,noexec,relatime)" ]]

  docker_stop "$SYSCONT_NAME"
}

# Privileged container security (privileged with respect to sys container context only)
@test "dind privileged security" {

  SYSCONT_NAME=$(docker_run --rm nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run --privileged --rm -d alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  # For each procfs and sysfs file associated with a non-namespaced resource,
  # verify that it's not possible to modify its value

  local all_non_ns=( "${PROC_SYS_NON_NS[@]}" "${SYS_NON_NS[@]}" )

  for entry in "${all_non_ns[@]}"; do
    eval $entry
    file=${e[0]}
    type=${e[1]}

    docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"cat $file\""
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

    docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"echo $sc_new > $file\""
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Permission denied" ]]
  done

  docker_stop "$SYSCONT_NAME"
}

@test "dind privileged ubuntu-disco" {

  SYSCONT_NAME=$(docker_run --rm nestybox/ubuntu-disco-docker:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$SYSCONT_NAME"
}

@test "dind privileged ubuntu-bionic" {

  SYSCONT_NAME=$(docker_run --rm nestybox/ubuntu-bionic-docker:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$SYSCONT_NAME"
}

@test "dind privileged debian-stretch" {

  SYSCONT_NAME=$(docker_run --rm nestybox/debian-stretch-docker:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$SYSCONT_NAME"
}

# Run docker inside a privileged container inside a sys container (!)
@test "dind privileged docker" {

  # launch sys cont
  SYSCONT_NAME=$(docker_run --rm nestybox/debian-stretch-docker:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  # launch priv container inside sys cont
  docker exec "$SYSCONT_NAME" sh -c "docker run --privileged --rm -d nestybox/alpine-docker:latest tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"dockerd > /var/log/dockerd-log 2>&1 &\""
  [ "$status" -eq 0 ]

  sleep 3

  # launch container inside priv container inside sys cont
  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"docker run --rm -d busybox tail -f /dev/null\""
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"docker ps --format \"{{.ID}}\"\""
  [ "$status" -eq 0 ]
  INNER_INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"docker exec $INNER_INNER_CONT_NAME sh -c \"busybox | head -1\"\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$SYSCONT_NAME"
}

# TODO: write tests that verify docker storage & networking inside a priv container inside a sys container
