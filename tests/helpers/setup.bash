#!/bin/bash

# sysboxd integration test setup helpers
#
# Note: based on a similar file in the OCI runc integration tests
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.

SYSCONT_NAME=""

WORK_DIR="/tmp"
INTEGRATION_ROOT=$(dirname "$(readlink -f "$BASH_SOURCE")")
RECVTTY="${INTEGRATION_ROOT}/../../sysbox-runc/contrib/cmd/recvtty/recvtty"
BUNDLES="${INTEGRATION_ROOT}/../../sys-container/bundles"

CONSOLE_SOCKET="$WORK_DIR/console.sock"

BUSYBOX_TAR_GZ="$BUNDLES/busybox.tar.gz"
BUSYBOX_BUNDLE="$WORK_DIR/busyboxtest"

DEBIAN_TAR_GZ="$BUNDLES/debian.tar.gz"
DEBIAN_BUNDLE="$WORK_DIR/debiantest"

# Root state path.
ROOT=$(mktemp -d "$WORK_DIR/runc.XXXXXX")

RUNC=sysbox-runc

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

# retry wrapper for bats 'run' commands
#
# Note: the command being retried must not be a bats 'run' command (such
# as those in tests/helpers/run.sh)
function retry_run() {
  local attempts=$1
  shift
  local delay=$1
  shift
  local i

  for ((i = 0; i < attempts; i++)); do
    run "$@"
    if [ "$status" -eq 0 ]; then
	return 0
    fi
    sleep $delay
  done

  echo "Command \"$@\" failed $attempts times. Output: $status"
  false
}

# Wrapper for sysbox-runc
function __sv_runc() {
  command $RUNC ${RUNC_FLAGS} --log /proc/self/fd/2 --root "$ROOT" "$@"
}

# Wrapper for sysbox-runc spec, which takes only one argument (the bundle path).
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

# setup_bundle tar-gz-path setup-path
function setup_bundle() {
  local tar_gz=$1
  local bundle=$2

  setup_recvtty
  mkdir -p "$bundle"/rootfs

  tar --exclude './dev/*' -C "$bundle"/rootfs -xzf "$tar_gz"

  # set bundle ownership per sysbox-runc requirements
  if [ -n "$SHIFT_UIDS" ]; then
    chown -R root:root "$bundle"
  else
    chown -R "$UID_MAP":"$GID_MAP" "$bundle"
  fi

  # Restrict path to bundle when using uid-shift, as required by
  # sysbox-runc's shiftfs mount security check
  if [ -n "$SHIFT_UIDS" ]; then
    chmod 700 "$bundle"
  fi

  cd "$bundle"
  runc_spec
}

# teardown_bundle bundle_path container_name
function teardown_bundle() {
  local bundle="$1"
  local container="$2"
  cd "$INTEGRATION_ROOT"
  teardown_running_container "$container"
  teardown_recvtty
  rm -f -r "$bundle"
}

function setup_busybox() {
  setup_bundle "$BUSYBOX_TAR_GZ" "$BUSYBOX_BUNDLE"
}

# teardown_busybox container_name
function teardown_busybox() {
  local container="$1"
  teardown_bundle "$BUSYBOX_BUNDLE" "$container"
}

function setup_debian() {
  setup_bundle "$DEBIAN_TAR_GZ" "$DEBIAN_BUNDLE"
}

# teardown_debian container_name
function teardown_debian() {
  local container="$1"
  teardown_bundle "$DEBIAN_BUNDLE" "$container"
}
