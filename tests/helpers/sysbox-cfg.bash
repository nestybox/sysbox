#!/bin/bash -x

# Obtain sysbox daemons' runtime parameters.
function sysbox_get_cmdline_flags() {
	local daemon=$1
	local -n optionsArray=$2

	if [[ ${daemon} != "sysbox-fs" ]] && [[ ${daemon} != "sysbox-mgr" ]]; then
		return 1
	fi

	# Obtain the sysbox daemon's runtime parameters and dump them into an array
	# to be returned to callee.
	local pid=$(pgrep ${daemon})
	optionsStr=$(ps -p ${pid} -o args | tail -1 | cut -d' ' -f2-)
	read -a optionsArray <<< ${optionsStr}
}

# Adds the given flag(s) to the given sysbox cmdline options array
function sysbox_add_cmdline_flags() {
	local all_args=("$@")
	local -n optionsArray=$1
	local flags="${all_args[@]:1}"
	local found

	for f in ${flags}; do
		found=false
		for param in "${optionsArray[@]}"; do
			if [[ ${param} == "${f}" ]]; then
				found=true
				break
			fi
		done
		if [[ $found == false ]]; then
			optionsArray+=("${f}")
		fi
	done
}

# Remove the given flag(s) from the given sysbox cmdline options array
function sysbox_rm_cmdline_flags() {
	local all_args=("$@")
	local -n optionsArray=$1
	local flags="${all_args[@]:1}"

	for f in ${flags}; do
		optionsArray=( "${optionsArray[@]/${f}}" )
	done
}
