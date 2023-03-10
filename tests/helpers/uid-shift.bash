#!/bin/bash

#
# Uid shifting helper functions
#

SYSBOX_LOG_FILE="/var/log/sysbox-mgr.log"

function sysbox_mgr_log_search() {

	# Because Sysbox may restart multiple times during the tests (with difference
	# cmd line flags in each restart), this function only searches the sysbox-mgr
	# log since the last restart.

	local search_term=$1
	if [ -n "$SB_INSTALLER" ]; then
		lastStartLine=$(journalctl -u sysbox-mgr | grep -n "Starting ..." | tail -1 | cut -f1 -d:)
		journalctl -u sysbox-mgr | tail -n +$lastStartLine | grep -iq "$search_term"
	else
		lastStartLine=$(grep -n "Starting ..." /var/log/sysbox-mgr.log | tail -1 | cut -f1 -d:)
		tail -n +$lastStartLine $SYSBOX_LOG_FILE | grep -iq "$search_term"
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

function sysbox_rootfs_cloning_disabled() {
	ps -fu root | grep "$(pidof sysbox-mgr)" | grep -q "disable-rootfs-cloning"
}

function sysbox_rootfs_cloning_enabled() {
	! sysbox_rootfs_cloning_disabled
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
	sysbox_using_shiftfs && ! sysbox_using_idmapped_mnt
}

function sysbox_using_rootfs_cloning() {
	! sysbox_using_overlayfs_on_idmapped_mnt && ! sysbox_using_shiftfs && ! sysbox_rootfs_cloning_disabled
}
