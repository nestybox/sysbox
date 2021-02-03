#!/usr/bin/env bats

. $(dirname ${BASH_SOURCE[0]})/setup.bash

#
# Bats command execution wrappers
#

# Call this from setup() to run a single test
#
# E.g.,
# function setup() {
#    run_only_test "disable_ipv6 lookup"
#    other_setup_actions
# }
#
# or
#
# function setup() {
#    run_only_test_num 2
#    other_setup_actions
# }

run_only_test() {
  if [ "$BATS_TEST_DESCRIPTION" != "$1" ]; then
    skip
  fi
}

run_only_test_num() {
  if [ "$BATS_TEST_NUMBER" -ne "$1" ]; then
    skip
  fi
}

# Wrapper for sysbox-runc using bats
function sv_runc() {
  run __sv_runc "$@"

  # Some debug information to make life easier. bats will only print it if the
  # test failed, in which case the output is useful.
  echo "sysbox-runc $@ (status=$status):" >&2
  echo "$output" >&2
}

# Wrapper for docker using bats
function docker() {
  run __docker "$@"

  # Debug info (same as sv_runc())
  echo "docker $@ (status=$status):" >&2
  echo "$output" >&2
}

# Need this to avoid recursion on docker()
function __docker() {
  command docker "$@"
}

# Executes docker run with sysbox-runc; returns the container id
function docker_run() {
  docker run --runtime=sysbox-runc -d "$@"
  [ "$status" -eq 0 ]

  docker ps --format "{{.ID}}"
  [ "$status" -eq 0 ]

  echo "$output" | head -1
}

# Stops a docker container immediately
function docker_stop() {
  [[ "$#" == 1 ]]

  local id="$1"

  echo "Stopping $id ..."

  if [ -z "$id" ]; then
    return 1
  fi

  docker stop -t0 "$id"
}

# Run a background process under bats
function bats_bg() {
  # To prevent background processes from hanging bats, we need to
  # close FD 3; see https://github.com/sstephenson/bats/issues/80#issuecomment-174101686
  "$@" 3>/dev/null &
}

function systemd_env() {
	ret=$(file /sbin/init)
	if [[ "$ret" =~ "symbolic link to /lib/systemd/systemd" ]]; then
		return 0
	else
		return 1
	fi
}

function sysbox_mgr_start() {

	# Note: here we assume sysbox-mgr is started with this command
	cmd="/usr/local/sbin/sysbox-mgr --log /var/log/sysbox-mgr.log"

	if [ -n "$SB_INSTALLER" ]; then
		systemd_unit="/lib/systemd/system/sysbox-mgr.service"

		cmd_old=$(grep "^ExecStart" $systemd_unit | awk -F "ExecStart=" '{print $2_}')
		cmd_new="${cmd} $@"
		sed -i "s@${cmd_old}@${cmd_new}@g" $systemd_unit

		systemctl daemon-reload
		systemctl restart sysbox
	else
		bats_bg ${cmd} $@
	fi

	sleep 2
	retry_run 10 1 grep -q "Ready" /var/log/sysbox-mgr.log
}

function sysbox_mgr_stop() {
  if [ -n "$SB_INSTALLER" ]; then
    systemctl stop sysbox
  else
    kill $(pidof sysbox-mgr)
  fi

  retry_run 10 1 sysbox_mgr_stopped
}

function sysbox_mgr_stopped() {
	run pgrep sysbox-mgr
	if [ "$status" -eq 0 ]; then
		return 1
	else
		return 0
	fi
}

function sysbox_fs_start() {

	# Note: here we assume sysbox-fs is started with this command
	cmd="/usr/local/sbin/sysbox-fs --log /var/log/sysbox-fs.log"

	if [ -n "$SB_INSTALLER" ]; then
		systemd_unit="/lib/systemd/system/sysbox-fs.service"

		cmd_old=$(grep "^ExecStart" $systemd_unit | awk -F "ExecStart=" '{print $2_}')
		cmd_new="${cmd} $@"
		sed -i "s@${cmd_old}@${cmd_new}@g" $systemd_unit

		systemctl daemon-reload
		systemctl restart sysbox
		sleep 1
	else
		bats_bg ${cmd} $@
	fi

	# TODO: find a better way to know when sysbox-fs is ready
	sleep 2
}

function sysbox_fs_stop() {
  if [ -n "$SB_INSTALLER" ]; then
     systemctl stop sysbox
  else
    kill $(pidof sysbox-fs)
  fi

  retry_run 10 1 sysbox_fs_stopped
}

function sysbox_fs_stopped() {
   run pgrep sysbox-fs
	if [ "$status" -eq 0 ]; then
		return 1
	else
		return 0
	fi
}

function sysbox_start() {

	# NOTE: for sysbox, just being in a systemd environment is not sufficient to
	# know if we are using the sysbox systemd services (i.e, we could have installed
	# sysbox from source). Thus we check for SB_INSTALLER instead of systemd_env.

	if [ -n "$SB_INSTALLER" ]; then
		systemctl start sysbox
	else
		bats_bg sysbox -t
	fi

	sleep 2
}

function sysbox_stop() {
	if [ -n "$SB_INSTALLER" ]; then
		systemctl stop sysbox
	else
		kill $(pidof sysbox-fs) && kill $(pidof sysbox-mgr)
	fi

  retry_run 10 1 sysbox_fs_stopped
  retry_run 10 1 sysbox_mgr_stopped
}

function sysbox_stopped() {
   run pgrep "sysbox-fs|sysbox-mgr"
	if [ "$status" -eq 0 ]; then
		return 1
	else
		return 0
	fi
}

function dockerd_start() {
  if systemd_env; then
    systemctl start docker.service
    sleep 2
  else
    bats_bg dockerd $@ > /var/log/dockerd.log 2>&1
    sleep 2
  fi
}

function dockerd_stop() {
  if systemd_env; then
    systemctl stop docker.service
    sleep 1
  else
    local pid=$(pidof dockerd)
    kill $pid
    sleep 1
    if [ -f /var/run/docker.pid ]; then rm /var/run/docker.pid; fi
  fi
}
