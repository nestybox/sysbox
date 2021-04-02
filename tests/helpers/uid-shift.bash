#!/bin/bash

load ../helpers/run

#
# Uid shifting helper functions
#

function host_supports_uid_shifting() {
	# Note: for now, host support for uid-shifting implies the presence of the
	# "shiftfs" module on the host's kernel. In the future, once support for
	# ID-mapped mounts is added in Sysbox, uid-shifting will alternatively mean
	# that the host kernel supports ID-mapped mounts.
	modprobe shiftfs;
}
