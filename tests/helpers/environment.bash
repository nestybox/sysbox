#!/bin/bash

#
# Environment specific routines.
#

# Dockerd default configuration dir/file.
export dockerCfgDir="/etc/docker"
export dockerCfgFile="${dockerCfgDir}/daemon.json"

# Default MTU value associated to egress-interface.
export default_mtu=1500

# Returns container's egress interface mtu.
function egress_iface_mtu() {

	if jq --exit-status 'has("mtu")' ${dockerCfgFile} >/dev/null; then
		local mtu=$(jq --exit-status '."mtu"' ${dockerCfgFile} 2>&1)

		if [ ! -z "$mtu" ] && [ "$mtu" -lt 1500 ]; then
			echo $mtu
		else
			echo $default_mtu
		fi
	else
		echo $default_mtu
	fi
}

function get_distro() {
	cat /etc/os-release | grep "^ID=" | cut -d "=" -f2 | tr -d '"'
}

function get_distro_release() {
	local distro=$(get_distro)

	if [[ ${distro} == centos || \
		${distro} == redhat || \
		${distro} == almalinux || \
		${distro} == rockylinux || \
		${distro} == fedora ]]; then
		cat /etc/os-release | grep "^VERSION_ID" | cut -d "=" -f2 | tr -d '"' | cut -d "." -f1
	else
		cat /etc/os-release | grep "^VERSION_CODENAME" | cut -d "=" -f2
	fi
}

function get_kernel_release() {
	uname -r
}

function get_platform() {
	local arch=$(uname -m)

	if [[ ${arch} == "x86_64" ]]; then
		echo "amd64"
	elif [[ ${arch} == "aarch64" ]]; then
		echo "arm64"
	elif [[ ${arch} == "arm32" ]]; then
		echo "arm"
	else
		echo "unsupported"
	fi
}

function get_kernel_headers_path() {
	local distro=$(get_distro)
	local kernel_rel=$(get_kernel_release)

	if [[ ${distro} == "centos" || \
		${distro} == "redhat" || \
		${distro} == "almalinux" || \
		${distro} == "rockylinux" || \
		${distro} == "fedora" ]]; then
		echo "/usr/src/kernels/${kernel_rel}"
	else
		echo "/usr/src/linux-headers-${kernel_rel}"
	fi
}

# Returns kernel's release in semver format (e.g. 5.4.1)
function get_kernel_release_semver() {
	echo $(uname -r | cut -d'-' -f1)
}

# Compare two versions in SemVer format.
#
# Examples:  (1.0.1, 1.0.1) = 0
#            (1.0.1, 1.0.2) = 2
#            (1.0.1, 1.0.0) = 1
#            (1, 1.0) = 0
#            (3.0.4.10, 3.0.4.2) = 1
#            (5.0.0-22, 5.0.0-22) = 0
#            (5.0.0-22, 5.0.0-21) = 1
#            (5.0.0-21, 5.0.0-22) = 2
#
function version_compare() {

	if [[ $1 == $2 ]]; then
		return 0
	fi

	local IFS='.|-'
	local i ver1=($1) ver2=($2)

	# Fill empty fields in ver1 with zeros.
	for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
		ver1[i]=0
	done

	for ((i = 0; i < ${#ver1[@]}; i++)); do
		if [[ -z ${ver2[i]} ]]; then
			# Fill empty fields in ver2 with zeros.
			ver2[i]=0
		fi
		if ((10#${ver1[i]} > 10#${ver2[i]})); then
			return 1
		fi
		if ((10#${ver1[i]} < 10#${ver2[i]})); then
			return 2
		fi
	done

	return 0
}

# Compare semantic versions; takes two semantic version numbers of the form
# x.y.z (or x.y), and returns 0 if the first is less than the
# second, and 1 otherwise.
function semver_lt() {
	version_compare $1 $2
	if [ "$?" -eq "2" ]; then
		return 0
	else
		return 1
	fi
}

# Compare semantic versions; takes two semantic version numbers of the form
# x.y.z (or x.y), and returns 0 if the first is greater than or equal to the
# second, and 1 otherwise.
function semver_ge() {
	version_compare $1 $2
	if [ "$?" -ne "2" ]; then
		return 0
	else
		return 1
	fi
}

function get_root_capabilities() {
	echo "$(sudo cat /proc/self/status | grep CapEff | awk '{print $2}')"
}
