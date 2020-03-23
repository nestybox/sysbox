#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls
#

load ../helpers/run
load ../helpers/syscall
load ../helpers/docker

# verify that explicit mounts of procfs inside a sys container are backed by
# sysbox-fs.
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
@test "mount non-procfs" {

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
@test "mount procfs path-resolution" {

  # TODO: test chmod dir permissions & path-resolution

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # absolute path
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative path
  docker exec "$syscont_name" bash -c "cd /root/l1 && mount -t proc proc l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # .. in path
  docker exec "$syscont_name" bash -c "cd /root/l1/l2 && mount -t proc proc ../../../root/l1/l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # . in path
  docker exec "$syscont_name" bash -c "cd /root/l1/l2 && mount -t proc proc ./proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cd $mnt_path && mount -t proc proc ."
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink
  docker exec "$syscont_name" bash -c "cd /root && ln -s l1/l2 l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "cd /root && mount -t proc proc l2link/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "rm /root/l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink at end
  docker exec "$syscont_name" bash -c "cd /root && ln -s l1/l2/proc proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "cd /root && mount -t proc proc proclink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "rm /root/proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # abs symlink
  docker exec "$syscont_name" bash -c "cd /root && ln -s /root/l1/l2/proc abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "cd /root && mount -t proc proc abslink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path
  docker exec "$syscont_name" bash -c "rm /root/abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "umount $mnt_path"
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
@test "mount procfs perm" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # root user can mount
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # a non-root user can't mount (needs cap_sys_admin)
  docker exec "$syscont" bash -c "useradd -m -u 1000 someone"
  [ "$status" -eq 0 ]

  docker exec -u 1000:1000 "$syscont" bash -c "mkdir -p /home/someone/l1/l2/proc && mount -t proc proc /home/someone/l1/l2/proc"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

@test "mount procfs capability checks" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # root user without CAP_SYS_ADMIN can't mount
  docker exec "$syscont" bash -c "capsh --inh=\"\" --drop=cap_sys_admin -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -ne 0 ]

  # root user without CAP_DAC_OVERRIDE, CAP_DAC_READ_SEARCH can't mount if path is non-searchable
  docker exec "$syscont" bash -c "chmod 400 /root/l1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "capsh --inh=\"\" --drop=cap_dac_override,cap_dac_read_search -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -ne 0 ]

  # a non-root user with appropriate caps can perform the mount; we use the
  # mountProcDac program to obtain these caps.

  make -C "$SYSBOX_ROOT/tests/scr/capRaise"

  docker exec "$syscont" bash -c "useradd -u 1000 someone"
  [ "$status" -eq 0 ]

   # copy mountProcDac program and set file caps on it
  docker cp "$SYSBOX_ROOT/tests/scr/capRaise/mountProcDac" "$syscont:/usr/bin"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "chown someone:someone /usr/bin/mountProcDac"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c 'setcap "cap_sys_admin,cap_dac_read_search,cap_dac_override=p" /usr/bin/mountProcDac'
  [ "$status" -eq 0 ]

  # perform the mount with mountProcDac
  docker exec -u 1000:1000 "$syscont" bash -c "mountProcDac $mnt_path"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "mount procfs in namespaces" {

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

@test "mount procfs dind" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont_name" bash -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" bash -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont_name $inner_cont_name /proc

  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name sh -c \"echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Read-only file system" ]]

  docker_stop "$syscont_name"
}

@test "mount procfs dind privileged" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont_name" bash -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" bash -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont_name $inner_cont_name /proc priv

  # verify that changing nf_conntrack_max within the privileged inner container affects the value in the sys container
  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name sh -c \"echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq 65535 ]

  # verify that changing nf_conntrack_max within the sys container affects the value in the privileged inner container
  docker exec "$syscont_name" bash -c "echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name sh -c \"cat /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]
  [ $output -eq 65536 ]

  docker_stop "$syscont_name"
}

@test "mount procfs dind privileged (ubuntu)" {

  local syscont_name=$(docker_run --rm nestybox/ubuntu-disco-docker:latest tail -f /dev/null)

  docker exec -d "$syscont_name" bash -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont_name

  docker exec "$syscont_name" bash -c "docker run --privileged --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont_name $inner_cont_name /proc priv

  # verify that changing nf_conntrack_max within the privileged inner container affects the value in the sys container
  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name sh -c \"echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq 65535 ]

  # verify that changing nf_conntrack_max within the sys container affects the value in the privileged inner container
  docker exec "$syscont_name" bash -c "echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "docker exec $inner_cont_name sh -c \"cat /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]
  [ $output -eq 65536 ]

  docker_stop "$syscont_name"
}

@test "mount procfs hidepid" {

  #local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local syscont_name=$(docker_run --rm ubuntu tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # mount proc with hidepid=2
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "mount -o remount,hidepid=2 $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont_name $mnt_path

  # root user can see pid 1
  docker exec "$syscont_name" bash -c "ls $mnt_path | grep -w 1"
  [ "$status" -eq 0 ]

  # non-root user can't see pid 1
  docker exec -u 1000:1000 "$syscont_name" bash -c "ls $mnt_path | grep -w 1"
  [ "$status" -eq 1 ]

  docker_stop "$syscont_name"
}

@test "mount procfs read-only" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -o ro -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont_name $mnt_path ro

  docker exec "$syscont_name" bash -c "echo 0 > $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Read-only file system" ]]

  docker_stop "$syscont_name"
}

@test "mount procfs remount busy" {

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

@test "multiple procfs in one syscont" {

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
  verify_syscont_procfs_mnt $syscont_name $mnt_path1

  # mount procfs on a second path
  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path2"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path2

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
  verify_syscont_procfs_mnt $syscont_name $mnt_path2

  docker exec "$syscont_name" bash -c "umount $mnt_path2"
  [ "$status" -eq 0 ]

  docker_stop "$syscont_name"
}

@test "multiple procfs in multiple syscont" {

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
  [ $output -eq $nf_max0 ]

  docker exec "$syscont_name0" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq $nf_max0 ]

  # the change of nf conntrack max in the first syscont must not affect the other syscont
  docker exec "$syscont_name1" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -ne $nf_max0 ]

  docker exec "$syscont_name1" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -ne $nf_max0 ]

  docker_stop "$syscont_name0"
  docker_stop "$syscont_name1"
}

@test "multiple procfs in multiple syscont (ubuntu)" {

  local mnt_path=/tmp/proc

  syscont_name0=$(docker_run --rm nestybox/ubuntu-disco-docker:latest tail -f /dev/null)
  syscont_name1=$(docker_run --rm nestybox/ubuntu-disco-docker:latest tail -f /dev/null)

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
  [ $output -eq $nf_max0 ]

  docker exec "$syscont_name0" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq $nf_max0 ]

  # the change of nf conntrack max in the first syscont must not affect the other syscont
  docker exec "$syscont_name1" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -ne $nf_max0 ]

  docker exec "$syscont_name1" bash -c "cat $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -ne $nf_max0 ]

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

  docker exec "$syscont_name" bash -c "mount | grep \"proc on $mnt_path\" | grep \"ro,\" | sed \"s/\/root//\""
  [ "$status" -eq 0 ]
  local mnt_proc_ro=$output

  [[ "$proc_ro" == "$mnt_proc_ro" ]]

  # verify that masked paths between /proc and $mnt_path match
  docker exec "$syscont_name" bash -c "mount | egrep \"udev on /proc|tmpfs on /proc\""
  [ "$status" -eq 0 ]
  local proc_masked=$output

  docker exec "$syscont_name" bash -c "mount | egrep \"udev on $mnt_path|tmpfs on $mnt_path\" | sed \"s/\/root//\""
  [ "$status" -eq 0 ]
  local mnt_proc_masked=$output

  [[ "$proc_masked" == "$mnt_proc_masked" ]]

  docker_stop "$syscont_name"
}

# Verify sysbox-fs ignores self-referencing bind mounts over procfs sysbox-fs backed submounts
@test "bind mount ignore" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont_name $mnt_path

  # self-referencing bind mounts
  for node in "${procfs_emu[@]}"; do
    docker exec "$syscont_name" bash -c "mount --bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
  done

  verify_syscont_procfs_mnt $syscont_name $mnt_path

  # root user without CAP_SYS_ADMIN can't bind mount
  docker exec "$syscont_name" bash -c "capsh --inh=\"\" --drop=cap_sys_admin -- -c \"mount --bind $mnt_path/sys $mnt_path/sys\""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "permission denied" ]]

  # root user without CAP_DAC_OVERRIDE, CAP_DAC_READ_SEARCH can't bind-mount if path is non-searchable
  docker exec "$syscont_name" bash -c "chmod 666 /root/l1"
  docker exec "$syscont_name" bash -c "capsh --inh=\"\" --drop=cap_dac_override,cap_dac_read_search -- -c \"mount --bind $mnt_path/sys $mnt_path/sys\""
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Permission denied" ]]

  docker_stop "$syscont_name"
}

# Verify sysbox-fs handles remounts over sysbox-fs backed portions of procfs correctly
@test "procfs remount" {

  # test read-write procfs mount with read-only remounts of proc/sys, proc/uptime, etc.

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  for node in "${procfs_emu[@]}"; do
    docker exec "$syscont_name" bash -c "mount --bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont_name" bash -c "mount -o remount,bind,ro $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont_name" bash -c "mount | grep $mnt_path/$node | grep sysboxfs"
    [ "$status" -eq 0 ]

    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse (ro," ]]
  done

  docker_stop "$syscont_name"

  # test read-only procfs mount with read-write remounts of proc/sys, proc/uptime, etc.

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -o ro -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  for node in "${procfs_emu[@]}"; do
    docker exec "$syscont_name" bash -c "mount --bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont_name" bash -c "mount -o remount,bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont_name" bash -c "mount | grep $mnt_path/$node | grep sysboxfs"
    [ "$status" -eq 0 ]

    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse (rw," ]]
  done

  docker_stop "$syscont_name"
}

@test "procfs unmount" {

  # verify that unmounting /proc also unmounts the sysbox-fs backed submounts

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont_name" bash -c "umount /proc"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid argument" ]]

  docker exec "$syscont_name" bash -c "mount | grep \"proc on /proc\""
  [ "$status" -eq 0 ]
  docker exec "$syscont_name" bash -c "mount | grep \"sysboxfs on /proc\""
  [ "$status" -eq 0 ]

  # mount and unmount /root/proc, verify unmounting proc unmounts the sysbox-fs backed submounts

  local mnt_path=/root/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont_name $mnt_path

  docker exec "$syscont_name" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount | grep \"proc on $mnt_path\""
  [ "$status" -eq 1 ]
  docker exec "$syscont_name" bash -c "mount | grep \"sysboxfs on $mnt_path\""
  [ "$status" -eq 1 ]

  docker_stop "$syscont_name"
}

# verify that it's not possible to do unmounts of procfs sysbox-fs backed submounts
@test "procfs partial unmount" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # try to unmount procfs sysbox-fs backed submounts (sysbox-fs should ignore the unmount)
  for node in "${procfs_emu[@]}"; do
    docker exec "$syscont_name" bash -c "umount /proc/$node"
    [ "$status" -eq 0 ]
  done

  verify_syscont_procfs_mnt $syscont_name /proc

  # mount proc at /root/proc
  local mnt_path=/root/proc

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont_name" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont_name $mnt_path

  # try to unmount procfs sysbox-fs backed submounts (sysbox-fs should ignore the unmount)
  for node in "${procfs_emu[@]}"; do
    docker exec "$syscont_name" bash -c "umount $mnt_path/$node"
    [ "$status" -eq 0 ]
  done

  verify_syscont_procfs_mnt $syscont_name $mnt_path

  docker_stop "$syscont_name"
}

# Verify that rbind operations can be successfully completed when there are sysbox-fs
# emulated procfs and sysfs subtrees. Also, verify that in this scenario, a partial
# unmount of a sysbox-fs emulated resource is allowed. The goal here is to mimic
# systemd's expected behavior during 'systemd-resolver' and 'systemd-network' daemon
# initializations.
@test "procfs rbind partial unmount" {

  local syscont_name=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/run/systemd/unit-root

  docker exec "$syscont_name" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # mount-rbind operation to mimic systemd behavior
  docker exec -d "$syscont_name" bash -c "mount --rbind / $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont_name $mnt_path/proc
  #verify_syscont_sysfs_mnt $syscont_name $mnt_path2/sys

  # Unmount procfs sysbox-fs backed submounts. As we are in systemd's path, sysbox-fs
  # should honor this request.
  for node in "${procfs_emu[@]}"; do
    docker exec "$syscont_name" bash -c "umount $mnt_path/proc/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont_name" bash -c "mount | egrep \"$mnt_path/proc/$node \""
    [ "$status" -eq 1 ]
  done

  docker_stop "$syscont_name"
}
