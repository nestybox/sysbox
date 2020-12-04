#!/bin/bash

#
# filesystem test helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

# sysbox-fs sys container "/proc" mounts
SYSFS_PROC="/proc/uptime \
            /proc/sys \
            /proc/swaps"

# In the future sysbox-fs will do these ones too ..
# SYSFS_PROC="/proc/cpuinfo \
#             /proc/cgroups \
#             /proc/devices \
#             /proc/diskstats \
#             /proc/loadavg \
#             /proc/meminfo \
#             /proc/pagetypeinfo \
#             /proc/partitions \
#             /proc/stat"

# sysbox-fs' "/proc/sys" emulated nodes. This array is utilized in "procSys.bats"
# to compare procfs hierarchies inside a sys-container with the one obtained in
# plain namespaced contexts (unshare). Note that not all emulated resources need
# to be exposed here, just the ones that mismatch between these two contexts being
# compared.
SYSFS_PROC_SYS="/proc/sys/net/netfilter/nf_conntrack_max \
		/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close_wait \
		/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established \
                /proc/sys/net/ipv4/vs/expire_nodest_conn \
                /proc/sys/net/ipv4/vs/expire_quiescent_template \
                /proc/sys/net/ipv4/vs/conn_reuse_mode \
                /proc/sys/net/ipv4/vs/conntrack \
                /proc/sys/net/unix/max_dgram_qlen"

# Given an 'ls -l' listing of a single file, verifies the permissions and ownership
function verify_perm_owner() {
  if [ $# -le 3 ]; then
     return 1
  fi

  local want_perm=$1
  local want_uid=$2
  local want_gid=$3
  shift 3
  local listing=$@

  local perm=$(echo "${listing}" | awk '{print $1}')
  local uid=$(echo "${listing}" | awk '{print $3}')
  local gid=$(echo "${listing}" | awk '{print $4}')

  # Notice that we are only comparing 10 characters (skiping the last one) on permisions
  # field to avoid conflicts in scenarios where selinux is enabled (i.e. "-rw-r--r--.").
  [[ "${perm:0:9}" == "${want_perm:0:9}" ]] && [[ "$uid" == "$want_uid" ]] && [[ "$gid" == "$want_gid" ]]
}

# Given an 'ls -l' listing of a single file, verifies it's read-only root:root
function verify_root_ro() {
    verify_perm_owner "-r--r--r--" "root" "root" "$@"
}

# Given an 'ls -l' listing of a single file, verifies it's read-write root:root
function verify_root_rw() {
    verify_perm_owner "-rw-r--r--" "root" "root" "$@"
}

# Returns the storage available on the given directory (must be a mountpoint)
function fs_avail() {
  dir=$1
  diskAvail=$(df $dir | grep $dir | awk '{print $4}')
  # "df" returns storage in units of KB; convert to bytes.
  echo $(($diskAvail*1024))
}

# Finds out if selinux is enabled by looking at the file-system extended attributes.
function selinux_on() {

  if ls -l /proc/uptime | cut -d" " -f1 | tail -c 2 | egrep -q "\."; then
    return 0
  else
    return 1
  fi
}

# Returns linux distro running on the host (technically, in the test-priv container).
function get_host_distro() {
  local distro=$(cat /etc/os-release | awk -F"=" '/^ID=/ {print $2}' | tr -d '"')
  echo $distro
}
