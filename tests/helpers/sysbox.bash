#!/usr/bin/env bats

. $(dirname ${BASH_SOURCE[0]})/systemd.bash
. $(dirname ${BASH_SOURCE[0]})/run.bash

function sysbox_mgr_start() {

	# Note: here we assume sysbox-mgr is started with this command
	cmd="/usr/bin/sysbox-mgr --log /var/log/sysbox-mgr.log"

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

function sysbox_mgr_started() {
	tail -f /var/log/sysbox-mgr.log | grep -q Ready
}

function sysbox_fs_started() {
	tail -f /var/log/sysbox-fs.log | grep -q Ready
}

function sysbox_fs_start() {

	# Note: here we assume sysbox-fs is started with this command
	cmd="/usr/bin/sysbox-fs --log /var/log/sysbox-fs.log"

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

	sleep 2
	retry_run 10 1 grep -q "Ready" /var/log/sysbox-fs.log
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
		if [ -n "$DEBUG_ON" ]; then
			bats_bg sysbox -t -d
		else
			bats_bg sysbox -t
		fi
	fi

  retry_run 10 1 sysbox_fs_started
  retry_run 10 1 sysbox_mgr_started

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

# Wrapper for "sysbox-runc" command using bats
function sv_runc() {
  run __sv_runc "$@"

  # Some debug information to make life easier. bats will only print it if the
  # test failed, in which case the output is useful.
  echo "sysbox-runc $@ (status=$status):" >&2
  echo "$output" >&2
}

# Obtain sysbox daemons' runtime parameters.
function sysbox_extract_running_options() {
	local daemon=$1
	local -n optionsArray=$2

	if [[ ${daemon} == "sysbox-fs" ]]; then
		run pgrep "sysbox-fs"
		if [ "$status" -ne 0 ]; then
			return
		fi
	elif [[ ${daemon} == "sysbox-mgr" ]]; then
		if [ "${status}" -ne 0 ]; then
			return
		fi
	fi
	local pid=${output}

	# Obtain the runtime parameters and dump them into an array to be returned
	# to callee.
	optionsStr=$(ps -p ${pid} -o args | tail -1 | cut -d' ' -f2-)
	read -a optionsArray <<< ${optionsStr}
}

function allow_immutable_remounts() {
	local options

	sysbox_extract_running_options "sysbox-fs" options

	for param in "${options[@]}"; do
		if [[ ${param} == "--allow-immutable-remounts=true" ]] ||
			[[ ${param} == "--allow-immutable-remounts=\"true\"" ]]; then
			return 0
		fi
	done

	return 1
}

function allow_immutable_unmounts() {
	local options

	sysbox_extract_running_options "sysbox-fs" options

	for param in "${options[@]}"; do
		if [[ ${param} == "--allow-immutable-unmounts=false" ]] ||
			[[ ${param} == "--allow-immutable-unmounts=\"false\"" ]]; then
			return 1
		fi
	done

	return 0
}
