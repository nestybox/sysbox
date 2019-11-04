#!/usr/bin/env bats

#
# Test for creating sys containers images with docker images inside
#

load ../helpers/run

SYSCONT_NAME=""

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "build with inner images" {

  # Reconfigure Docker's default runtime to sysbox-runc
  #
  # Note: for some reason this does not work on bats. I worked-around
  # it by configuring the docker daemon in the sysbox test container
  # to use the sysbox-runc as it's default runtime.
  #
  # dockerd_stop
  # cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
  # (cat /etc/docker/daemon.json 2>/dev/null || echo '{}') | jq '. + {"default-runtime": "sysbox-runc"}' > /tmp/tmp.json
  # mv /tmp/tmp.json /etc/docker/daemon.json
  # dockerd_start

  # randomly pre-mount shiftfs on /lib/modules/<kernel-version>, to test whether the sysbox-mgr
  # shiftfs manager detects and skips mounting shiftfs on this directory

  local premount="false"
  if [[ $((RANDOM % 2)) == "0" ]]; then
    mount -t shiftfs -o mark /lib/modules/$(uname -r) /lib/modules/$(uname -r)
    premount="true"
  fi

  # do a docker build with appropriate dockerfile
  pushd .
  cd tests/dind
  docker build --no-cache -t nestybox/sc-with-inner-img:latest .
  [ "$status" -eq 0 ]

  docker image prune -f
  [ "$status" -eq 0 ]

  # run generated container to confirm that images are embedded in it
  SYSCONT_NAME=$(docker_run --rm nestybox/sc-with-inner-img:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  # run an inner container using one of the embedded images
  docker exec "$SYSCONT_NAME" sh -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  docker image rm nestybox/sc-with-inner-img:latest
  docker image prune -f

  if [[ $premount == "true" ]]; then
    umount /lib/modules/$(uname -r)
  fi

  popd

  # revert dockerd default runtime config
  # dockerd_stop
  # mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
  # dockerd_start
}

@test "commit with inner images" {

  SYSCONT_NAME=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "echo testdata > /root/testfile"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker pull busybox:latest"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker pull alpine:latest"
  [ "$status" -eq 0 ]

  # commit the sys container image
  docker image rm -f nestybox/alpine-docker-dbg:commit
  [ "$status" -eq 0 ]
  docker commit "$SYSCONT_NAME" nestybox/alpine-docker-dbg:commit
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
  docker image prune -f

  # launch a sys container with the committed image
  SYSCONT_NAME=$(docker_run --rm nestybox/alpine-docker-dbg:commit)

  # verify testfile is present
  docker exec "$SYSCONT_NAME" sh -c "cat /root/testfile"
  [ "$status" -eq 0 ]
  [[ "$output" == "testdata" ]]

  # make sure to remove docker.pid & containerd.pid before launching docker (it's in the committed image)
  docker exec "$SYSCONT_NAME" sh -c "rm -f /var/run/docker.pid && rm -f /run/docker/containerd/containerd.pid"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  # verify images are present
  docker exec "$SYSCONT_NAME" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  # run an inner container using one of the embedded images
  docker exec "$SYSCONT_NAME" sh -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  docker image rm nestybox/alpine-docker-dbg:commit
}
