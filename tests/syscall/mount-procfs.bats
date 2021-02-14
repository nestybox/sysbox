#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls for procfs mounts
#

load ../helpers/run
load ../helpers/syscall
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

#
# Tests that verify procfs mounts within the sys container
#

# Verify a new procfs mount is a replica of the procfs mount at /proc
@test "mount procfs" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  # mount procfs at $mnt_path and verify it's backed by sysbox-fs
  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  # verify the newly mounted procfs is protected by the sys container's userns
  docker exec "$syscont" bash -c "echo 1 > $mnt_path/sys/kernel/panic_print"
  [ "$status" -eq 1 ]
  [[ "$output" =~ /root/proc/sys/kernel/panic_print:\ Permission\ denied ]]

  # verify that read-only paths between /proc and $mnt_path match
  docker exec "$syscont" bash -c "mount | grep \"proc on /proc\" | grep \"ro,\""
  [ "$status" -eq 0 ]
  local proc_ro=$output

  docker exec "$syscont" bash -c "mount | grep \"proc on $mnt_path\" | grep \"ro,\" | sed \"s/\/root//\""
  [ "$status" -eq 0 ]
  local mnt_proc_ro=$output

  [[ "$proc_ro" == "$mnt_proc_ro" ]]

  # verify that masked paths between /proc and $mnt_path match
  docker exec "$syscont" bash -c "mount | egrep \"udev on /proc|tmpfs on /proc\""
  [ "$status" -eq 0 ]
  local proc_masked=$output

  docker exec "$syscont" bash -c "mount | egrep \"udev on $mnt_path|tmpfs on $mnt_path\" | sed \"s/\/root//\""
  [ "$status" -eq 0 ]
  local mnt_proc_masked=$output

  [[ "$proc_masked" == "$mnt_proc_masked" ]]

  docker_stop "$syscont"
}

@test "mount procfs read-only" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -o ro -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path ro

  docker exec "$syscont" bash -c "echo 0 > $mnt_path/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Read-only file system" ]]

  docker_stop "$syscont"
}

@test "mount procfs redudant" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"

  # For some reason, Fedora & Debian kernels are allowing overlapping mount instructions
  # to succeed. Will handle these cases differently for now, but we may need to revisit
  # this approach as this is something that may be applicable to all recent kernels (5.8+).
  if lsb_release -d | egrep -q Fedora ||
     lsb_release -d | egrep -q Debian; then
    [ "$status" -eq 0 ]
  else
    [ "$status" -eq 255 ]
    [[ "$output" =~ "Resource busy" ]]
  fi

  docker_stop "$syscont"
}

@test "procfs consistency" {

  # verify an emulated node under procfs show consistent value when
  # between /proc and a second procfs mountpoint within the sys container
  local mnt_path=/root/proc
  local node=sys/net/netfilter/nf_conntrack_max

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # mount procfs at $mnt_path
  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat /proc/$node"
  [ "$status" -eq 0 ]
  local val_mount1="$output"

  docker exec "$syscont" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  local val_mount2="$output"

  [[ "$val_mount1" == "$val_mount2" ]]

  # change value in /proc in verify the change is reflected in $mnt_path
  val_mount1=$((val_mount1 - 100))
  docker exec "$syscont" bash -c "echo $val_mount1 > /proc/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat /proc/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount1" ]]

  docker exec "$syscont" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount1" ]]

  # change value in $mnt_path in verify the change is reflected in /proc
  val_mount2=$((val_mount1 - 100))
  docker exec "$syscont" bash -c "echo $val_mount2 > $mnt_path/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount2" ]]

  docker exec "$syscont" bash -c "cat /proc/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount2" ]]

  docker_stop "$syscont"
}

@test "procfs consistency 2" {

  # verify an emulated node under procfs show consistent value when
  # procfs mounted at different points with the sys container.
  local mnt_path1=/tmp/proc1
  local mnt_path2=/tmp/proc2
  local node=sys/net/netfilter/nf_conntrack_max

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "mkdir -p $mnt_path1"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "mkdir -p $mnt_path2"
  [ "$status" -eq 0 ]

  # mount procfs on a first path
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path1"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path1

  # mount procfs on a second path
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path2"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path2

  # verify node value is consistent in both mount paths
  docker exec "$syscont" bash -c "cat $mnt_path1/$node"
  [ "$status" -eq 0 ]
  local val1="$output"

  docker exec "$syscont" bash -c "cat $mnt_path2/$node"
  [ "$status" -eq 0 ]
  local val2="$output"

  [ $val1 -eq $val2 ]

  # change node val in the first path, verify the change is reflected in the second path
  val1=$((val1 - 100))

  docker exec "$syscont" bash -c "echo $val1 > $mnt_path1/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat $mnt_path2/$node"
  [ "$status" -eq 0 ]
  local val2="$output"

  [ $val1 -eq $val2 ]

  # unmount procfs on the first path and verify the second path is unaffected
  docker exec "$syscont" bash -c "umount $mnt_path1"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path2

  docker exec "$syscont" bash -c "umount $mnt_path2"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "procfs consistency (multiple syscont)" {

  local mnt_path=/tmp/proc
  local node=sys/net/netfilter/nf_conntrack_max

  syscont0=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  syscont1=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # mount procfs inside the first sys container
  docker exec "$syscont0" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # mount procfs inside the other sys container
  docker exec "$syscont1" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont1" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # change node value in the first syscont and verify that works
  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  local val0="$output"

  val0=$((val0 - 100))

  docker exec "$syscont0" bash -c "echo $val0 > $mnt_path/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "cat /proc/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  # the change in the first syscont must not affect the other syscont
  docker exec "$syscont1" bash -c "cat /proc/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker exec "$syscont1" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker_stop "$syscont0"
  docker_stop "$syscont1"
}

@test "procfs consistency (multiple procfs in multiple syscont)" {

  local mnt_path=/tmp/proc
  local node=sys/net/netfilter/nf_conntrack_max

  syscont0=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker:latest tail -f /dev/null)
  syscont1=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker:latest tail -f /dev/null)

  # mount procfs inside the first sys container
  docker exec "$syscont0" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # mount procfs inside the other sys container
  docker exec "$syscont1" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont1" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # change node value in the first syscont and verify that works
  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  local val0="$output"

  val0=$((val0 - 100))

  docker exec "$syscont0" bash -c "echo $val0 > $mnt_path/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "cat /proc/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  # the change of node value in the first syscont must not affect the other syscont
  docker exec "$syscont1" bash -c "cat /proc/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker exec "$syscont1" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker_stop "$syscont0"
  docker_stop "$syscont1"
}

# Verify remount of procfs causes a remount of all submounts.
@test "procfs remount" {

  # Alpine image not working -- refer to issue #645 https://github.com/nestybox/sysbox/issues/645
  # local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local syscont=$(docker_run --rm ubuntu tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  # remount to read-only
  docker exec "$syscont" bash -c "mount -o remount,bind,ro $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path ro

  # revert remount to read-write
  docker exec "$syscont" bash -c "mount -o remount,bind,rw $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  docker_stop "$syscont"
}

@test "mount procfs hidepid" {

  #local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local syscont=$(docker_run --rm ubuntu tail -f /dev/null)
  local mnt_path=/tmp/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # mount proc with hidepid=2
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "mount -o remount,hidepid=2 $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  # root user can see pid 1
  docker exec "$syscont" bash -c "ls $mnt_path | grep -w 1"
  [ "$status" -eq 0 ]

  # non-root user can't see pid 1
  docker exec -u 1000:1000 "$syscont" bash -c "ls $mnt_path | grep -w 1"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

# Verify remounts of procfs submounts
@test "procfs remount submount" {

  # test read-write procfs mount with read-only remounts of submounts
  local mnt_path=/root/sys
  local node=sys/net/netfilter/nf_conntrack_max

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  for node in "${PROCFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "mount --bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont" bash -c "mount -o remount,bind,ro $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont" bash -c "mount | grep $mnt_path/$node | grep sysboxfs"
    [ "$status" -eq 0 ]

    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse (ro," ]]
  done

  docker_stop "$syscont"

  # test read-only procfs mount with read-write remounts of submounts
  syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -o ro -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  for node in "${PROCFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "mount --bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont" bash -c "mount -o remount,bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont" bash -c "mount | grep $mnt_path/$node | grep sysboxfs"
    [ "$status" -eq 0 ]

    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse (rw," ]]
  done

  docker_stop "$syscont"
}

@test "procfs move mount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path1=/tmp/proc1
  local mnt_path2=/tmp/proc2

  docker exec "$syscont" bash -c "mkdir -p $mnt_path1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mkdir -p $mnt_path2"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -o move $mnt_path1 $mnt_path2"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path2

  docker_stop "$syscont"
}

@test "procfs unmount" {

  # verify that unmounting /proc is not allowed

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "umount /proc"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "busy" ]]

  docker exec "$syscont" bash -c "mount | grep \"proc on /proc\""
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "mount | grep \"sysboxfs on /proc\""
  [ "$status" -eq 0 ]

  # mount and unmount procfs at /root/proc, verify this works well

  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"proc on $mnt_path\""
  [ "$status" -eq 1 ]
  docker exec "$syscont" bash -c "mount | grep \"sysboxfs on $mnt_path\""
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

# verify that it's not possible to do unmounts of procfs submounts managed by sysbox-fs
@test "procfs unmount submount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # try to unmount procfs sysbox-fs backed submounts (sysbox-fs should ignore the unmount)
  for node in "${PROCFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "umount /proc/$node"
    [ "$status" -eq 0 ]
  done

  verify_syscont_procfs_mnt $syscont /proc

  # mount procfs somewhere else
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  # try to unmount procfs submounts (sysbox-fs should ignore the unmount)
  for node in "${PROCFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "umount $mnt_path/$node"
    [ "$status" -eq 0 ]
  done

  verify_syscont_procfs_mnt $syscont $mnt_path

  docker_stop "$syscont"
}

#
# Tests that verify procfs mounts within unshared namespaces and inner containers
#

@test "procfs mount in inner container" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" bash -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" bash -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont $inner_cont_name /proc

  docker exec "$syscont" bash -c "docker exec $inner_cont_name sh -c \"echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Read-only file system" ]]

  docker_stop "$syscont"
}

@test "procfs mount in inner privileged container" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" bash -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" bash -c "docker run --privileged --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont $inner_cont_name /proc priv

  # verify that changing nf_conntrack_max within the privileged inner container affects the value in the sys container
  docker exec "$syscont" bash -c "docker exec $inner_cont_name sh -c \"echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq 65535 ]

  # verify that changing nf_conntrack_max within the sys container affects the value in the privileged inner container
  docker exec "$syscont" bash -c "echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "docker exec $inner_cont_name sh -c \"cat /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]
  [ $output -eq 65536 ]

  docker_stop "$syscont"
}

@test "procfs mount in inner privileged container (ubuntu)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker:latest tail -f /dev/null)

  docker exec -d "$syscont" bash -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" bash -c "docker run --privileged --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  verify_inner_cont_procfs_mnt $syscont $inner_cont_name /proc priv

  # verify that changing nf_conntrack_max within the privileged inner container affects the value in the sys container
  docker exec "$syscont" bash -c "docker exec $inner_cont_name sh -c \"echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]
  [ $output -eq 65535 ]

  # verify that changing nf_conntrack_max within the sys container affects the value in the privileged inner container
  docker exec "$syscont" bash -c "echo 65536 > /proc/sys/net/netfilter/nf_conntrack_max"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "docker exec $inner_cont_name sh -c \"cat /proc/sys/net/netfilter/nf_conntrack_max\""
  [ "$status" -eq 0 ]
  [ $output -eq 65536 ]

  docker_stop "$syscont"
}

@test "unshare & mount procfs" {

  skip "FAILS (SYSBOX ISSUE #590)"

  # verify mount of procfs by a sys container process that unshares
  # its namespaces; this should create stacked mounts on /proc in the
  # process' mount ns, such as:
  #
  # ├─/proc          proc                   proc    rw,nosuid,nodev,noexec,relatime
  # ├─/proc/swaps    sysboxfs[/proc/swaps]  fuse    rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
  # ├─/proc/sys      sysboxfs[/proc/sys]    fuse    rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
  # ├─/proc/uptime   sysboxfs[/proc/uptime] fuse    rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
  # ├─/proc/bus      proc[/bus]             proc    ro,relatime
  # ...
  # ├─/proc/scsi     tmpfs                  tmpfs   ro,relatime,uid=165536,gid=165536
  # └─/proc          proc                   proc    rw,nosuid,nodev,noexec,relatime
  #   ├─/proc/swaps  sysboxfs[/proc/swaps]  fuse    rw,nosuid,nodev,noexec,relatime
  #   ├─/proc/sys    sysboxfs[/proc/sys]    fuse    rw,nosuid,nodev,noexec,relatime
  #   ├─/proc/uptime sysboxfs[/proc/uptime] fuse    rw,nosuid,nodev,noexec,relatime
  #
  # That is, we should see stacked mounts backed by sysbox-fs for /proc/sys, /proc/uptime, etc.

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "unshare -i -m -n -p -u -f --mount-proc=/proc bash -c \"mount | grep sysbox\""
  local sysbox_mounts=$output

  for mnt in "${PROCFS_EMU[@]}"; do
    run sh -c "echo \"$sysbox_mounts\" | grep /proc/$mnt | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
  done

  docker_stop "$syscont"
}

@test "inner container unshare & mount procfs" {

  skip "FAILS (SYSBOX ISSUE #590)"

  # verify mount of procfs by an inner container process that unshares
  # its namespaces; this should create stacked mounts on /proc in the
  # process' mount ns.

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" bash -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" bash -c "docker run --privileged --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont_name="$output"

  # unshare & mount proc from withn inner container; verify looks good
  docker exec "$syscont" bash -c "docker exec $inner_cont_name sh -c \"unshare -i -m -n -p -u -f --mount-proc=/proc sh -c \"mount | grep sysbox\"\""
  [ "$status" -eq 0 ]

  local sysbox_mounts=$output

  for mnt in "${PROCFS_EMU[@]}"; do
    run sh -c "echo \"$sysbox_mounts\" | grep /proc/$mnt | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
  done

  docker_stop "$syscont"
}

#
# Tests that verify bind-mounts on procfs
#

@test "bind from procfs" {

  # verify /proc can be bind-mounted somewhere else

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # --bind
  docker exec "$syscont" bash -c "mount --bind /proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # --rbind
  docker exec "$syscont" bash -c "mount --rbind /proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "bind-to-self procfs submount" {

  # Verify sysbox-fs ignores bind-to-self on submounts
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local node=/proc/sys

  docker exec "$syscont" bash -c "mount --bind $node $node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep -w $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # unmount is also ignored
  docker exec "$syscont" bash -c "umount $node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep -w $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  docker_stop "$syscont"
}

@test "bind over procfs submount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local node=/proc/uptime

  # Verify bind-mount over submount managed by sysbox-fs
  # (we choose /proc/uptime as an example, though in practice it wouldn't make sense)

  docker exec "$syscont" bash -c "mount --bind /dev/null $node"
  [ "$status" -eq 0 ]

  # At this point we should have stacked mounts over /proc/uptime.
  #
  # │ └─/proc/uptime     sysboxfs[/proc/uptime]  fuse    rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
  # │   └─/proc/uptime   tmpfs[/null]            tmpfs   rw,nosuid,size=65536k,mode=755

  docker exec "$syscont" bash -c "mount | grep $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  docker exec "$syscont" bash -c "umount $node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # Verify bind-mount over submount not managed by sysbox-fs
  node=/proc/devices

  docker exec "$syscont" bash -c "mount --bind /dev/null $node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  docker exec "$syscont" bash -c "umount $node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep $node"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

@test "bind from procfs base mount" {

  # Verify that bind-mounting /proc to another directory causes the
  # bind-mount to be applied recursively on all sysbox-fs managed
  # submounts.

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --bind /proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep $mnt_path"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

@test "bind from procfs submount" {

  # Verify that bind-mounting /proc/sys to another directory causes the
  # bind-mount to be applied only to /proc/sys and no other sysbox-fs
  # submounts.

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --bind /proc/sys $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep -w $mnt_path"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sysboxfs on $mnt_path type fuse (rw," ]]

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep $mnt_path"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

#
# Tests that verify bind-mount propagation on procfs
#

@test "procfs private" {

  # verify a bind mount of /proc to another dir has private propagation by default

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --bind /proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont /proc
  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "mount --bind /dev/null /proc/version"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/proc/version\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tmpfs on /proc/version type tmpfs (rw," ]]

  docker_stop "$syscont"
}

@test "procfs shared" {

  # verify a shared propagation

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-rshared /proc"
  [ "$status" -eq 0 ]

  # Note: mount --bind works, but causes the bind source (/proc) to
  # get redundant binds under the submounts. That's likely because
  # with --bind, sysbox-fs is doing the bind-mounts of the submounts
  # explicitly. With --rbind, we don't see the redundant submounts.
  # It's a cosmetic issue, not a functional one.

  docker exec "$syscont" bash -c "mount --rbind /proc $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont /proc
  verify_syscont_procfs_mnt $syscont $mnt_path

  # verify /proc -> $mnt_path propagation

  docker exec "$syscont" bash -c "mount --bind /dev/null /proc/version"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/proc/version\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "tmpfs on /proc/version type tmpfs (rw," ]]
  [[ "${lines[1]}" =~ "tmpfs on $mnt_path/version type tmpfs (rw," ]]

  # verify $mnt_path -> /proc propagation

  docker exec "$syscont" bash -c "umount $mnt_path/version"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/proc/version\""
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

@test "procfs slave" {

  # verify a slave propagation

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-rshared /proc"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --rbind /proc $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-rslave $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_procfs_mnt $syscont /proc
  verify_syscont_procfs_mnt $syscont $mnt_path

  # verify master (/proc) -> slave ($mnt_path) propagation

  docker exec "$syscont" bash -c "mount --bind /dev/null /proc/version"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/proc/version\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "tmpfs on /proc/version type tmpfs (rw," ]]
  [[ "${lines[1]}" =~ "tmpfs on $mnt_path/version type tmpfs (rw," ]]

  # verify slave ($mnt_path) -> master (/proc) non-propagation

  docker exec "$syscont" bash -c "umount $mnt_path/version"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/proc/version\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tmpfs on /proc/version type tmpfs (rw," ]]

  docker_stop "$syscont"
}

@test "procfs unbindable" {

  # verify unbindable propagation

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-runbindable /proc"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --rbind /proc $mnt_path"
  [ "$status" -ne 0 ]

  docker_stop "$syscont"
}
