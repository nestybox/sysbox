#!/bin/bash

#
# Uid shifting helper functions
#

SYSBOX_LOG_FILE="/var/log/sysbox-mgr.log"

function sysbox_mgr_log_search {
	local search_term=$1

	if [ -n "$SB_INSTALLER" ]; then
		journalctl -u sysbox-mgr | grep -iq "$search_term"
	else
		grep -iq "$search_term" $SYSBOX_LOG_FILE
	fi
}

function kernel_supports_shiftfs() {
	sysbox_mgr_log_search "Shiftfs works properly: yes"
}

function kernel_supports_shiftfs_on_overlayfs() {
	sysbox_mgr_log_search "Shiftfs-on-overlayfs works properly: yes"
}

function kernel_supports_idmapped_mnt() {
	sysbox_mgr_log_search "ID-mapped mounts supported by kernel: yes"
}

function kernel_supports_overlayfs_on_idmapped_mnt() {
	sysbox_mgr_log_search "Overlayfs on ID-mapped mounts supported by kernel: yes"
}

function sysbox_idmapped_mnt_disabled {
	sysbox_mgr_log_search "Use of ID-mapped mounts disabled"
}

function sysbox_idmapped_mnt_enabled {
	! sysbox_idmapped_mnt_disabled
}

function sysbox_shiftfs_disabled {
	sysbox_mgr_log_search "Use of shiftfs disabled"
}

function sysbox_shiftfs_enabled {
	! sysbox_shiftfs_disabled
}

function sysbox_using_shiftfs {
	sysbox_shiftfs_enabled && kernel_supports_shiftfs
}

function sysbox_using_shiftfs_on_overlayfs {
	sysbox_shiftfs_enabled && kernel_supports_shiftfs_on_overlayfs
}

function sysbox_using_idmapped_mnt {
	sysbox_idmapped_mnt_enabled && kernel_supports_idmapped_mnt
}

function sysbox_using_overlayfs_on_idmapped_mnt {
	sysbox_idmapped_mnt_enabled && kernel_supports_overlayfs_on_idmapped_mnt
}

function sysbox_using_uid_shifting() {
	sysbox_using_idmapped_mnt || sysbox_using_shiftfs
}

function sysbox_using_all_uid_shifting() {
	sysbox_using_idmapped_mnt && sysbox_using_shiftfs
}

function sysbox_using_idmapped_mnt_only() {
	sysbox_using_idmapped_mnt && ! sysbox_using_shiftfs
}

function sysbox_using_shiftfs_only() {
	sysbox_using_idmapped_mnt && sysbox_using_shiftfs
}
