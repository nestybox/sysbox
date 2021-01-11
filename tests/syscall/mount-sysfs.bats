#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls for sysfs mounts
#

load ../helpers/run
load ../helpers/syscall
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# Verify a new sysfs mount is a replica of the sysfs mount at /sys
@test "mount sysfs" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/sys

  # mount sysfs at $mnt_path and verify it's backed by sysbox-fs
  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  # verify the newly mounted sysfs is protected by the sys container's userns
  docker exec "$syscont" bash -c "echo 2 > $mnt_path/kernel/profiling"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "$mnt_path"/kernel/profiling:\ Permission\ denied ]]

  docker_stop "$syscont"
}

@test "mount sysfs read-only" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -o ro -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path ro

  for node in "${SYSFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "echo 0 > $mnt_path/$node"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Read-only file system" ]]
  done

  docker_stop "$syscont"
}

@test "mount sysfs redudant" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/tmp/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 255 ]
  [[ "$output" =~ "Resource busy" ]]

  docker_stop "$syscont"
}

@test "sysfs consistency" {

  # verify an emulated node under sysfs show consistent value when
  # between /sys and a second sysfs mountpoint within the sys container
  local mnt_path=/root/sys
  local node=module/nf_conntrack/parameters/hashsize

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # mount sysfs at $mnt_path
  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat /sys/$node"
  [ "$status" -eq 0 ]
  local val_mount1="$output"

  docker exec "$syscont" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  local val_mount2="$output"

  [[ "$val_mount1" == "$val_mount2" ]]

  # change value in /sys in verify the change is reflected in $mnt_path
  val_mount1=$((val_mount1 - 100))
  docker exec "$syscont" bash -c "echo $val_mount1 > /sys/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat /sys/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount1" ]]

  docker exec "$syscont" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount1" ]]

  # change value in $mnt_path in verify the change is reflected in /sys
  val_mount2=$((val_mount1 - 100))
  docker exec "$syscont" bash -c "echo $val_mount2 > $mnt_path/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount2" ]]

  docker exec "$syscont" bash -c "cat /sys/$node"
  [ "$status" -eq 0 ]
  [[ "$output" == "$val_mount2" ]]

  docker_stop "$syscont"
}

@test "sysfs consistency 2" {

  # verify an emulated node under sysfs show consistent value when
  # sysfs mounted at different points with the sys container.
  local mnt_path1=/tmp/sys1
  local mnt_path2=/tmp/sys2
  local node=module/nf_conntrack/parameters/hashsize

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "mkdir -p $mnt_path1"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "mkdir -p $mnt_path2"
  [ "$status" -eq 0 ]

  # mount sysfs on a first path
  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path1"
  [ "$status" -eq 0 ]
  verify_syscont_sysfs_mnt $syscont $mnt_path1

  # mount sysfs on a second path
  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path2"
  [ "$status" -eq 0 ]
  verify_syscont_sysfs_mnt $syscont $mnt_path2

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

  # unmount sysfs on the first path and verify the second path is unaffected
  docker exec "$syscont" bash -c "umount $mnt_path1"
  [ "$status" -eq 0 ]
  verify_syscont_sysfs_mnt $syscont $mnt_path2

  docker exec "$syscont" bash -c "umount $mnt_path2"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "sysfs consistency (multiple syscont)" {

  local mnt_path=/tmp/sys
  local node=module/nf_conntrack/parameters/hashsize

  syscont0=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  syscont1=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # mount sysfs inside the first sys container
  docker exec "$syscont0" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  # mount sysfs inside the other sys container
  docker exec "$syscont1" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont1" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  # change node value in the first syscont and verify that works
  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  local val0="$output"

  val0=$((val0 - 100))

  docker exec "$syscont0" bash -c "echo $val0 > $mnt_path/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "cat /sys/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  # the change in the first syscont must not affect the other syscont
  docker exec "$syscont1" bash -c "cat /sys/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker exec "$syscont1" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker_stop "$syscont0"
  docker_stop "$syscont1"
}

@test "sysfs consistency (multiple procfs in multiple syscont)" {

  local mnt_path=/tmp/sys
  local node=module/nf_conntrack/parameters/hashsize

  syscont0=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker:latest tail -f /dev/null)
  syscont1=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-bionic-docker:latest tail -f /dev/null)

  # mount sysfs inside the first sys container
  docker exec "$syscont0" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  # mount sysfs inside the other sys container
  docker exec "$syscont1" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont1" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  # change node value in the first syscont and verify that works
  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  local val0="$output"

  val0=$((val0 - 100))

  docker exec "$syscont0" bash -c "echo $val0 > $mnt_path/$node"
  [ "$status" -eq 0 ]

  docker exec "$syscont0" bash -c "cat /sys/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  docker exec "$syscont0" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -eq $val0 ]

  # the change of node value in the first syscont must not affect the other syscont
  docker exec "$syscont1" bash -c "cat /sys/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker exec "$syscont1" bash -c "cat $mnt_path/$node"
  [ "$status" -eq 0 ]
  [ $output -ne $val0 ]

  docker_stop "$syscont0"
  docker_stop "$syscont1"
}

@test "sysfs remount" {

  # Verify remount of sysfs causes a remount of all submounts.

  # Alpine image not working -- refer to issue #645 https://github.com/nestybox/sysbox/issues/645
  # local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  # remount to read-only
  docker exec "$syscont" bash -c "mount -o remount,bind,ro $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path ro

  # verify sysfs is not affected by read-only remount on procfs (i.e.,
  # remount of sysbox-fs managed submounts was applied to the submount
  # only, not at the fuse filesystem level).
  verify_syscont_procfs_mnt $syscont /proc

  # revert remount to read-write
  docker exec "$syscont" bash -c "mount -o remount,bind,rw $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker_stop "$syscont"
}

@test "sysfs mount & remount (superblock)" {

  # Alpine image not working -- refer to issue #645 https://github.com/nestybox/sysbox/issues/645
  # local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  # remount to read-only at super-block level
  docker exec "$syscont" bash -c "mount -o remount,ro $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path ro

  # verify procfs is not affected by read-only remount on sysfs (i.e.,
  # remount of sysbox-fs managed submounts was applied to the submounts
  # only, not at the fuse filesystem level).
  verify_syscont_procfs_mnt $syscont /proc

  # revert remount to read-write
  docker exec "$syscont" bash -c "mount -o remount,rw $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker_stop "$syscont"
}

@test "/sys remount & mount (superblock)" {

  # Alpine image not working -- refer to issue #645 https://github.com/nestybox/sysbox/issues/645
  # local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # remount to read-only at super-block level on /sys
  docker exec "$syscont" bash -c "mount -o remount,ro /sys"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont /sys ro

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path ro

  # verify procfs is not affected by read-only remount on sysfs (i.e.,
  # remount of sysbox-fs managed submounts was applied to the submounts
  # only, not at the fuse filesystem level).
  verify_syscont_procfs_mnt $syscont /proc

  # revert remount to read-write (super-block level)
  docker exec "$syscont" bash -c "mount -o remount,rw /sys"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont /sys
  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker_stop "$syscont"
}

# Verify remounts of sysfs submounts
@test "sysfs remount submount" {

  # test read-write sysfs mount with read-only remounts of submounts
  local mnt_path=/root/sys
  local node=module/nf_conntrack/parameters/hashsize

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  for node in "${SYSFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "mount --bind $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont" bash -c "mount -o remount,bind,ro $mnt_path/$node $mnt_path/$node"
    [ "$status" -eq 0 ]
    docker exec "$syscont" bash -c "mount | grep $mnt_path/$node | grep sysboxfs"
    [ "$status" -eq 0 ]

    [[ "$output" =~ "sysboxfs on $mnt_path/$node type fuse (ro," ]]
  done

  docker_stop "$syscont"

  # test read-only sysfs mount with read-write remounts of submounts
  syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -o ro -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  for node in "${SYSFS_EMU[@]}"; do
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

@test "sysfs move mount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path1=/tmp/sys1
  local mnt_path2=/tmp/sys2

  docker exec "$syscont" bash -c "mkdir -p $mnt_path1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mkdir -p $mnt_path2"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -o move $mnt_path1 $mnt_path2"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path2

  docker_stop "$syscont"
}

@test "sysfs unmount" {

  # verify that unmounting /sys is not allowed

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "umount /sys"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not permitted" ]]

  docker exec "$syscont" bash -c "mount | grep \"sysfs on /sys\""
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "mount | grep \"sysboxfs on /sys\""
  [ "$status" -eq 0 ]

  # mount and unmount sysfs at /root/sys, verify this works well

  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"sysfs on $mnt_path\""
  [ "$status" -eq 1 ]
  docker exec "$syscont" bash -c "mount | grep \"sysboxfs on $mnt_path\""
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

# verify that it's not possible to do unmounts of sysfs submounts managed by sysbox-fs
@test "sysfs unmount submount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # try to unmount sysfs sysbox-fs backed submounts (sysbox-fs should prevent this
  # from happening).
  for node in "${SYSFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "umount /sys/$node"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not permitted" ]]
  done

  verify_syscont_sysfs_mnt $syscont /sys

  # mount sysfs somewhere else
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount -t sysfs sysfs $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  # try to unmount sysfs submounts (sysbox-fs should ignore the unmount)
  for node in "${SYSFS_EMU[@]}"; do
    docker exec "$syscont" bash -c "umount $mnt_path/$node"
    [ "$status" -eq 0 ]
  done

  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker_stop "$syscont"
}

#
# Tests that verify bind-mounts on sysfs
#

@test "bind from sysfs" {

  # verify /sys can be bind-mounted somewhere else

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # --bind
  docker exec "$syscont" bash -c "mount --bind /sys $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # --rbind
  docker exec "$syscont" bash -c "mount --rbind /sys $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker_stop "$syscont"
}

@test "bind-to-self sysfs submount" {

  # Verify sysbox-fs ignores bind-to-self on submounts
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local node=/sys/module/nf_conntrack/parameters/hashsize

  docker exec "$syscont" bash -c "mount --bind $node $node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep -w $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # Unmount of an immutable resource must not be allowed
  docker exec "$syscont" bash -c "umount $node"
  [ "$status" -eq 1 ]

  docker exec "$syscont" bash -c "mount | grep -w $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  docker_stop "$syscont"
}

@test "bind over sysfs submount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local node=/sys/module/nf_conntrack/parameters/hashsize

  # Verify bind-mount over submount managed by sysbox-fs
  docker exec "$syscont" bash -c "mount --bind /dev/null $node"
  [ "$status" -eq 0 ]

  # At this point we should have stacked mounts over $node
  docker exec "$syscont" bash -c "mount | grep $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  docker exec "$syscont" bash -c "umount $node"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep $node | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # Verify bind-mount over submount not managed by sysbox-fs
  node=/sys/kernel/profiling

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

@test "bind from sysfs base mount" {

  # Verify that bind-mounting /sys to another directory causes the
  # bind-mount to be applied recursively on all sysbox-fs managed
  # submounts.

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --bind /sys $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep $mnt_path"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

@test "bind from sysfs submount" {

  # Verify that bind-mounting a submount to another directory causes the
  # bind-mount to be applied only to that submount and no other sysbox-fs
  # submounts.

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local submount=/sys/module/nf_conntrack/parameters/hashsize
  local mnt_path=/root/hashsize

  docker exec "$syscont" bash -c "touch $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --bind $submount $mnt_path"
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

@test "sysfs private" {

  # verify a bind mount of /proc to another dir has private propagation by default

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --bind /sys $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont /sys
  verify_syscont_sysfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "mount --bind /dev/null /sys/kernel/profiling"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/sys/kernel/profiling\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tmpfs on /sys/kernel/profiling type tmpfs (rw," ]]

  docker_stop "$syscont"
}

@test "sysfs shared" {

  # verify a shared propagation

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-rshared /sys"
  [ "$status" -eq 0 ]

  # Note: mount --bind works, but causes the bind source (/sys) to
  # get redundant binds under the submounts. That's likely because
  # with --bind, sysbox-fs is doing the bind-mounts of the submounts
  # explicitly. With --rbind, we don't see the redundant submounts.
  # It's a cosmetic issue, not a functional one.

  docker exec "$syscont" bash -c "mount --rbind /sys $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont /sys
  verify_syscont_sysfs_mnt $syscont $mnt_path

  # verify /sys -> $mnt_path propagation

  docker exec "$syscont" bash -c "mount --bind /dev/null /sys/kernel/profiling"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/sys/kernel/profiling\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "tmpfs on /sys/kernel/profiling type tmpfs (rw," ]]
  [[ "${lines[1]}" =~ "tmpfs on $mnt_path/kernel/profiling type tmpfs (rw," ]]

  # verify $mnt_path -> /sys propagation

  docker exec "$syscont" bash -c "umount $mnt_path/kernel/profiling"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/sys/kernel/profiling\""
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

@test "sysfs slave" {

  # verify a slave propagation

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-rshared /sys"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --rbind /sys $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-rslave $mnt_path"
  [ "$status" -eq 0 ]

  verify_syscont_sysfs_mnt $syscont /sys
  verify_syscont_sysfs_mnt $syscont $mnt_path

  # verify master (/sys) -> slave ($mnt_path) propagation

  docker exec "$syscont" bash -c "mount --bind /dev/null /sys/kernel/profiling"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/sys/kernel/profiling\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "tmpfs on /sys/kernel/profiling type tmpfs (rw," ]]
  [[ "${lines[1]}" =~ "tmpfs on $mnt_path/kernel/profiling type tmpfs (rw," ]]

  # verify slave ($mnt_path) -> master (/sys) non-propagation

  docker exec "$syscont" bash -c "umount $mnt_path/kernel/profiling"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount | grep \"/sys/kernel/profiling\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tmpfs on /sys/kernel/profiling type tmpfs (rw," ]]

  docker_stop "$syscont"
}

@test "sysfs unbindable" {

  # verify unbindable propagation

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/sys

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --make-runbindable /sys"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mount --rbind /sys $mnt_path"
  [ "$status" -ne 0 ]

  docker_stop "$syscont"
}
