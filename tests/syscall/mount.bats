#!/usr/bin/env bats

#
# Verify syscall trapping & emulation on "mount" syscall
#

load ../helpers/run

# verifies the given sys container path contains a procfs mount backed by sysbox-fs
function verify_syscont_procfs_mnt() {
  ! [[ "$#" != 2 ]]
  local syscont_name=$1
  local mnt_path=$2

  docker exec "$syscont_name" bash -c "mount | grep $mnt_path | grep sysboxfs"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "sysboxfs on $mnt_path/swaps type fuse" ]]
  [[ "${lines[1]}" =~ "sysboxfs on $mnt_path/sys type fuse" ]]
  [[ "${lines[2]}" =~ "sysboxfs on $mnt_path/uptime type fuse" ]]

  true
}

# verify that explicit mounts of procfs inside a sys container are backed by sysbox-fs
@test "mount procfs" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  # mount procfs at $mnt_path and verify it's backed by sysbox-fs
  docker exec "$syscont_name" bash -c "mkdir $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont_name $mnt_path

  # verify nf_conntrack_max is exposed in $mnt_path and matches the one in /proc
  docker exec "$syscont_name" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  local nf_max_proc="$output"

  docker exec "$syscont_name" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  local nf_max_root_proc="$output"

  [[ "$nf_max_proc" == "$nf_max_root_proc" ]]

  # change nf_conntrack_max in /proc in verify the change is reflected in $mnt_path
  nf_max_proc=$((nf_max_proc - 100))
  docker exec "$syscont_name" bash -c "echo $nf_max_proc > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [[ "$output" == "$nf_max_proc" ]]

  docker exec "$syscont_name" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [[ "$output" == "$nf_max_proc" ]]

  # change nf_conntrack_max in $mnt_path in verify the change is reflected in /proc
  nf_max_proc=$((nf_max_proc - 100))
  docker exec "$syscont_name" bash -c "echo $nf_max_proc > $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [[ "$output" == "$nf_max_proc" ]]

  docker exec "$syscont_name" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [[ "$output" == "$nf_max_proc" ]]

  docker_stop "$syscont_name"
}

# Verify that non-procfs mounts inside a sys contaner are not backed by sysbox-fs
test "mount non-procfs" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # mount sysfs at /root/sys and verify it's not backed by sysbox-fs
  docker exec "$syscont_name" bash -c "mkdir /root/sys"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t sysfs sysfs /root/sys"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount | grep /root/sys"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sysfs on /root/sys type sysfs (rw,relatime)" ]]

  docker_stop "$syscont_name"
}

# verify that mounts of procfs inside a sys container undergo correct path resolution (per path_resolution(7))
test "mount procfs path-resolution" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # absolute path
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  umount "mnt_path"
  [ "$status" -eq 0 ]

  # relative path
  docker exec "$syscont_name" bash -c "cd /root/l1 && mount -t proc proc l2/proc"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  umount "mnt_path"
  [ "$status" -eq 0 ]

  # .. in path
  docker exec "$syscont_name" bash -c "cd /root/l1/l2 && mount -t proc proc ../../root/l1/l2/proc"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  umount "mnt_path"
  [ "$status" -eq 0 ]

  # . in path
  docker exec "$syscont_name" bash -c "cd /root/l1/l2 && mount -t proc proc ./proc"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  umount "mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cd $mnt_path && mount -t proc proc ."
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  umount "mnt_path"
  [ "$status" -eq 0 ]

  # symlink in middle
  docker exec "$syscont_name" bash -c "cd /root && ln -s l1/l2 l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "cd /root && mount -t proc proc l2link/proc"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "rm /root/l2link"
  [ "$status" -eq 0 ]
  umount "mnt_path"
  [ "$status" -eq 0 ]

  # symlink at end
  docker exec "$syscont_name" bash -c "cd /root && ln -s l1/l2/proc proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "cd /root && mount -t proc proc proclink"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "rm /root/proclink"
  [ "$status" -eq 0 ]
  umount "mnt_path"
  [ "$status" -eq 0 ]

  # invalid path
  docker exec "$syscont_name" bash -c "cd /root && mount -t proc proc invalidpath"
  [ "$status" -eq 255 ]
  [[ "$output" =~ "No such file or directory" ]]

  # TODO: overly long path (> MAXPATHLEN) returns in ENAMETOOLONG

  # TODO: mount syscall with empty mount path (should return ENOENT)
  # requires calling mount syscall directly

  docker_stop "$syscont_name"
}

# verify that mounts of procfs inside a sys container undergo correct permission checks
test "mount procfs perm" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # root user can mount
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path
  umount "mnt_path"
  [ "$status" -eq 0 ]

  # non-root user can't mount
  docker exec -u 1000:1000 "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "permission denied" ]]

  # root user without CAP_SYS_ADMIN can't mount
  docker exec "$syscont_name" bash -c "capsh --inh=\"\" --drop=cap_sys_admin -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "permission denied" ]]

  # root user without CAP_DAC_OVERRIDE, CAP_DAC_READ_SEARCH can't mount if path is non-searchable
  docker exec "$syscont_name" bash -c "chmod 666 /root/l1"
  docker exec "$syscont_name" bash -c "capsh --inh=\"\" --drop=cap_dac_override,cap_dac_read_search -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "permission denied" ]]
  docker exec "$syscont_name" bash -c "chmod 755 /root/l1"

  docker_stop "$syscont_name"
}

test "mount procfs in namespaces" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # mount of procfs from a process that unshares it's mount ns inside sys container
  docker exec "$syscont_name" bash -c "unshare -m bash -c \"mount -t proc proc $mnt_path && mount | grep $mnt_path\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "proc on /root/l1/l2/proc type proc (rw,relatime)" ]]

  # the sys container's mount ns should remain unchanged
  docker exec "$syscont_name" bash -c "mount | grep $mnt_path"
  [ "$status" -eq 1 ]

  docker_stop "$syscont_name"
}

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $1 docker ps"
}

function verify_inner_cont_procfs_mnt() {
  ! [[ "$#" != 2 ]]
  local syscont_name=$1
  local inner_cont_name=$2

  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name bash -c \"mount | grep sysboxfs\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "sysboxfs on /proc/swaps type fuse" ]]
  [[ "${lines[1]}" =~ "sysboxfs on /proc/sys type fuse" ]]
  [[ "${lines[2]}" =~ "sysboxfs on /proc/uptime type fuse" ]]

  true
}

test "mount procfs dind" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont_name" bash -c "dockerd > /var/log/dockerd.log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd $syscont_name

  docker exec "$syscont_name" bash -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont_name $inner_cont_name

  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name bash -c \"echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Read-only file system" ]]

  docker_stop "$syscont_name"
}

test "mount procfs dind privileged" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont_name" bash -c "dockerd > /var/log/dockerd.log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd $syscont_name

  docker exec "$syscont_name" bash -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont_name $inner_cont_name

  # verify that changing nf_conntrack_max within the privileged inner container affects the value in the sys container
  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name bash -c \"echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq 65535 ]

  # verify that changing nf_conntrack_max within the sys container affects the value in the privileged inner container
  docker exec "$syscont_name" bash -c "echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name bash -c \"cat /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]
  [ $output -eq 65536 ]

  docker_stop "$syscont_name"
}

test "mount procfs hidepid" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # mount proc with hidepid=2
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "mount -o remount,hidepid=2 $mnt_path"
  [ "$status" -eq 0 ]

  verify_procfs_mnt $syscont_name $mnt_path

  # root user can see pid 1
  docker exec "$syscont_name" bash -c "ls /tmp/proc | grep -w 1"
  [ "$status" -eq 0 ]

  # non-root user can't see pid 1
  docker exec -u 1000:1000 "$syscont_name" bash -c "ls /tmp/proc | grep -w 1"
  [ "$status" -eq 1 ]

  docker_stop "$syscont_name"
}

test "mount procfs read-only" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -o ro -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount | grep $mnt_path"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "proc on /tmp/proc type proc (ro,relatime)" ]]

  docker_stop "$syscont_name"
}

test "mount procfs remount busy" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 255 ]
  [[ "$output" =~ "Resource busy" ]]

  docker_stop "$syscont_name"
}

test "multiple procfs mounts in one syscont" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path1=/tmp/proc1
  local mnt_path2=/tmp/proc2

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path1"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path2"
  [ "$status" -eq 0 ]

  # mount procfs on a first path
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path1"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path1

  # mount procfs on a second path
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path2"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path2

  # verify nf_conntrack_max is consistent in both mount paths
  docker exec "$syscont_name" bash -c "cat $mnt_path1/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  local nf_max_path1="$output"

  docker exec "$syscont_name" bash -c "cat $mnt_path2/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  local nf_max_path2="$output"

  [ $nf_max_path1 -eq $nf_max_path2 ]

  # change nf_conntrack_max in the first path, verify the change is reflected in the second path
  nf_max_path1=$((nf_max_path1 - 100))

  docker exec "$syscont_name" bash -c "echo $nf_max_path1 > $mnt_path1/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cat $mnt_path2/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  local nf_max_path2="$output"

  [ $nf_max_path1 -eq $nf_max_path2 ]

  # unmount procfs on the first path and verify the second path is unaffected
  docker exec "$syscont_name" bash -c "umount $mnt_path1"
  [ "$status" -eq 0 ]
  verify_procfs_mnt $syscont_name $mnt_path2

  docker exec "$syscont_name" bash -c "umount $mnt_path2"
  [ "$status" -eq 0 ]

  docker_stop "$syscont_name"
}

test "multiple procfs in multiple syscont" {

  local mnt_path=/tmp/proc

  syscont_name0=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  syscont_name1=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # mount proc inside the first sys container
  docker exec "$syscont_name0" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name0" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # mount proc inside the other sys container
  docker exec "$syscont_name1" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name1" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # change nf conntrack max in the first syscont and verify that works
  docker exec "$syscont_name0" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  local nf_max0="$output"

  nf_max0=$((nf_max0 - 100))

  docker exec "$syscont_name0" bash -c "echo $nf_max0 > $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name0" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq $nf_max0 ]]

  docker exec "$syscont_name0" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq $nf_max0 ]]

  # the change of nf conntrack max in the first syscont must not affect the other syscont
  docker exec "$syscont_name1" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -ne $nf_max0 ]]

  docker exec "$syscont_name1" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -ne $nf_max0 ]]

  docker_stop "$syscont_name0"
  docker_stop "$syscont_name1"
}

# Verify a procfs remount honors the read-only and masked paths in the sys container's /proc mount
@test "procfs readonly and masked paths" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont_name" bash -c "mkdir $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # verify that read-only paths between /proc and $mnt_path match
  docker exec "$syscont_name" bash -c "mount | grep \"proc on /proc\" | grep \"ro,\""
  [ "$status" -eq 0 ]
  local proc_ro=$output

  docker exec "$syscont_name" bash -c "mount | grep \"proc on $mnt_path\" | grep \"ro,\""
  [ "$status" -eq 0 ]
  local mnt_proc_ro=$output

  [[ "$proc_ro" == "$mnt_proc_ro" ]]

  # verify that masked paths between /proc and $mnt_path match
  docker exec "$syscont_name" bash -c "mount | egrep \"udev on /proc|tmpfs on /proc\""
  [ "$status" -eq 0 ]
  local proc_masked=$output

  docker exec "$syscont_name" bash -c "mount | egrep \"udev on $mnt_path|tmpfs on $mnt_path\""
  [ "$status" -eq 0 ]
  local mnt_proc_masked=$output

  [[ "$proc_masked" == "$mnt_proc_masked" ]]
}
