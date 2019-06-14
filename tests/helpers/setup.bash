#!/bin/bash

#
# sysvisor integration test setup helpers
#
# Note: much code borrowed from the OCI runc integration tests
#

SYSCONT_NAME=""

WORK_DIR="/tmp"
INTEGRATION_ROOT=$(dirname "$(readlink -f "$BASH_SOURCE")")
RECVTTY="${INTEGRATION_ROOT}/../../sysvisor-runc/contrib/cmd/recvtty/recvtty"

CONSOLE_SOCKET="$WORK_DIR/console.sock"

BUSYBOX_IMAGE="$WORK_DIR/busybox.tar"
BUSYBOX_BUNDLE="$WORK_DIR/busyboxtest"

# Root state path.
ROOT=$(mktemp -d "$WORK_DIR/runc.XXXXXX")

RUNC=sysvisor-runc

RUNC_FLAGS="--no-kernel-check"

# sys container uid(gid) mapping
UID_MAP=100000
GID_MAP=100000
ID_MAP_SIZE=65536

# Retry a command $1 times until it succeeds. Wait $2 seconds between retries.
# (copied from runc/tests/integration/helpers.bash)
function retry() {
  local attempts=$1
  shift
  local delay=$1
  shift
  local i

  for ((i = 0; i < attempts; i++)); do
    "$@"
    if [ "$?" -eq 0 ]; then
	return 0
    fi
    sleep $delay
  done

  echo "Command \"$@\" failed $attempts times. Output: $?"
  false
}

# Wrapper for sysvisor-runc
function __sv_runc() {
  command $RUNC ${RUNC_FLAGS} --log /proc/self/fd/2 --root "$ROOT" "$@"
}

# Wrapper for sysvisor-runc spec, which takes only one argument (the bundle path).
function runc_spec() {
  ! [[ "$#" > 1 ]]

  local args=()
  local bundle=""

  if [ "$#" -ne 0 ]; then
    bundle="$1"
    args+=("--bundle" "$bundle")
  fi

  if [ -z "$SHIFT_UIDS" ]; then
    $RUNC spec "${args[@]}" --id-map "$UID_MAP $GID_MAP $ID_MAP_SIZE"
  else
    $RUNC spec "${args[@]}"
  fi
}

function get_busybox() {
  echo 'https://github.com/docker-library/busybox/raw/a0558a9006ce0dd6f6ec5d56cfd3f32ebeeb815f/glibc/busybox.tar.xz'
}

function setup_recvtty() {
  # We need to start recvtty in the background, so we double fork in the shell.
  ("$RECVTTY" --pid-file "$WORK_DIR/recvtty.pid" --mode null "$CONSOLE_SOCKET" &) &
}

function teardown_recvtty() {
  # When we kill recvtty, the container will also be killed.
  if [ -f "$WORK_DIR/recvtty.pid" ]; then
    kill -9 $(cat "$WORK_DIR/recvtty.pid")
  fi

  # Clean up the files that might be left over.
  rm -f "$WORK_DIR/recvtty.pid"
  rm -f "$CONSOLE_SOCKET"
}

function setup_busybox() {
  setup_recvtty
  mkdir "$BUSYBOX_BUNDLE"
  mkdir "$BUSYBOX_BUNDLE"/rootfs
  if [ -e "/testdata/busybox.tar" ]; then
    BUSYBOX_IMAGE="/testdata/busybox.tar"
  fi
  if [ ! -e $BUSYBOX_IMAGE ]; then
    curl -o $BUSYBOX_IMAGE -sSL `get_busybox`
  fi
  tar --exclude './dev/*' -C "$BUSYBOX_BUNDLE"/rootfs -xf "$BUSYBOX_IMAGE"

  # sysvisor-runc: set bundle ownership to match system
  # container's uid/gid map, except if using uid-shifting
  if [ -z "$SHIFT_UIDS" ]; then
    chown -R "$UID_MAP":"$GID_MAP" "$BUSYBOX_BUNDLE"
  fi

  # sysvisor-runc: restrict path to bundle when using
  # uid-shift, as required by sysvisor-runc's shiftfs
  # mount security check
  if [ -n "$SHIFT_UIDS" ]; then
    chmod 700 "$BUSYBOX_BUNDLE"
  fi

  cd "$BUSYBOX_BUNDLE"
  runc_spec
}

function teardown_running_container() {
  res=$(__sv_runc list)
  # $1 should be a container name such as "test_busybox"
  # here we detect "test_busybox "(with one extra blank) to avoid conflict prefix
  # e.g. "test_busybox" and "test_busybox_update"
  if [[ "${res}" == *"$1 "* ]]; then
    __sv_runc kill $1 KILL
    retry 10 1 eval "__sv_runc state '$1' | grep -q 'stopped'"
    __sv_runc delete $1
  fi
}

function teardown_busybox() {
  cd "$INTEGRATION_ROOT"
  teardown_recvtty
  teardown_running_container test_busybox
  rm -f -r "$BUSYBOX_BUNDLE"
}

function docker_stop() {
  [[ "$#" == 1 ]]
  local name=$1
  docker stop -t 0 "$name"
}
