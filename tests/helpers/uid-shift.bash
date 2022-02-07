#!/bin/bash

load ../helpers/run

#
# Uid shifting helper functions
#

function kernel_supports_shiftfs() {
	modprobe shiftfs >/dev/null 2>&1 && lsmod | grep -q shiftfs
}

function kernel_supports_idmapped_mnt() {

	local kernel_rel=$(uname -r)
	local rel_major=$(echo ${kernel_rel} | cut -d'.' -f1)
	local rel_minor=$(echo ${kernel_rel} | cut -d'.' -f2)

	[ ${rel_major} -gt 5 ] || ( [ ${rel_major} -eq 5 ] && [ ${rel_minor} -ge 12 ] )
}

function sysbox_idmapped_mnt_disabled {
	ps -fu | grep "$(pidof sysbox-mgr)" | grep -q "disable-idmapped-mount"
}

function sysbox_idmapped_mnt_enabled {
	ps -fu | grep "$(pidof sysbox-mgr)" | grep -qv "disable-idmapped-mount"
}

function sysbox_shiftfs_disabled {
	ps -fu | grep "$(pidof sysbox-mgr)" | grep -q "disable-shiftfs"
}

function sysbox_shiftfs_enabled {
	ps -fu | grep "$(pidof sysbox-mgr)" | grep -qv "disable-shiftfs"
}

function sysbox_using_idmapped_mnt() {
	if kernel_supports_idmapped_mnt && sysbox_idmapped_mnt_enabled; then
		return 0
	else
		return 1
	fi
}

function sysbox_using_shiftfs() {
	if kernel_supports_shiftfs && sysbox_shiftfs_enabled; then
		return 0
	else
		return 1
	fi
}

function sysbox_using_uid_shifting() {
	if sysbox_using_idmapped_mnt || sysbox_using_shiftfs; then
		return 0
	else
		return 1
	fi
}

function sysbox_using_all_uid_shifting() {
	if sysbox_using_idmapped_mnt && sysbox_using_shiftfs; then
		return 0
	else
		return 1
	fi
}

function sysbox_using_idmapped_mnt_only() {
	if sysbox_using_idmapped_mnt && ! sysbox_using_shiftfs; then
		return 0
	else
		return 1
	fi
}

function sysbox_using_shiftfs_only() {
	if ! sysbox_using_idmapped_mnt && sysbox_using_shiftfs; then
		return 0
	else
		return 1
	fi
}
