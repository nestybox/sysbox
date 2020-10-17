#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls for overlayfs mounts
#


load ../helpers/run
load ../helpers/syscall
load ../helpers/docker
load ../helpers/sysbox-health

ovfs_path="/var/lib/docker/overlay2"

function teardown() {
  sysbox_log_check
}

# Verify basic overlayfs mount instruction.
@test "mount overlayfs basic" {

  local lower_path="$ovfs_path"/root/lower
  local upper_path="$ovfs_path"/root/upper
  local work_path="$ovfs_path"/root/work
  local merge_path="$ovfs_path"/root/merge

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # Prepare mount setup.
  docker exec "$syscont" bash -c \
    "mkdir -p $lower_path $upper_path $work_path $merge_path"
  [ "$status" -eq 0 ]

  # Mount overlayfs at $merge_path.
  docker exec "$syscont" bash -c \
    "mount -t overlay overlay -olowerdir=$lower_path,upperdir=$upper_path,workdir=$work_path $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_mnt $syscont $merge_path

  # Umount overlayfs mountpoint.
  docker exec "$syscont" bash -c "umount $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_umnt $syscont $merge_path

  docker_stop "$syscont"
}

# Verify fs addition operations.
@test "mount overlayfs addition ops" {

  local lower_path="$ovfs_path"/root/lower
  local upper_path="$ovfs_path"/root/upper
  local work_path="$ovfs_path"/root/work
  local merge_path="$ovfs_path"/root/merge

  local lower_file="$ovfs_path"/root/lower/lower_file
  local lower_dir="$ovfs_path"/root/lower/lower_dir
  local lower_dir_file="$ovfs_path"/root/lower/lower_dir/lower_file
  local upper_file="$ovfs_path"/root/upper/upper_file
  local upper_dir="$ovfs_path"/root/upper/upper_dir
  local upper_dir_file="$ovfs_path"/root/upper/upper_dir/upper_file

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c \
    "mkdir -p $lower_path $upper_path $work_path $merge_path && \
     mkdir -p $lower_dir $upper_dir && \
     touch $lower_file $lower_dir_file $upper_file $upper_dir_file"
  [ "$status" -eq 0 ]

  # Mount overlayfs at $merge_path.
  docker exec "$syscont" bash -c \
    "mount -t overlay overlay -olowerdir=$lower_path,upperdir=$upper_path,workdir=$work_path $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_mnt $syscont $merge_path

  # Verify dir/file content in merge folder is the expected one.
  docker exec "$syscont" stat $lower_file $lower_dir $lower_dir_file $upper_file $upper_dir $upper_dir_file
  [ "$status" -eq 0 ]

  # Add new dir.
  docker exec "$syscont" bash -c "mkdir $merge_path/new_dir"
  [ "$status" -eq 0 ]

  # Add new file.
  docker exec "$syscont" bash -c "touch $merge_path/new_file"
  [ "$status" -eq 0 ]

  # Confirm new dir/file is present in merge layer.
  docker exec "$syscont" bash -c "stat $merge_path/new_dir $merge_path/new_file"
  [ "$status" -eq 0 ]

  # Confirm new dir/file is present in upper layer.
  docker exec "$syscont" bash -c "stat $upper_path/new_dir $upper_path/new_file"
  [ "$status" -eq 0 ]

  # Umount overlayfs mountpoint.
  docker exec "$syscont" bash -c "umount $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_umnt $syscont $merge_path

  docker_stop "$syscont"
}

# Verify fs deletion operations.
@test "mount overlayfs deletion ops" {

  local lower_path="$ovfs_path"/root/lower
  local upper_path="$ovfs_path"/root/upper
  local work_path="$ovfs_path"/root/work
  local merge_path="$ovfs_path"/root/merge

  local lower_dir="$ovfs_path"/root/lower/lower_dir
  local lower_file="$ovfs_path"/root/lower/lower_file
  local upper_dir="$ovfs_path"/root/upper/upper_dir
  local upper_file="$ovfs_path"/root/upper/upper_file

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c \
    "mkdir -p $lower_path $upper_path $work_path $merge_path && \
     mkdir -p $lower_dir $upper_dir && \
     touch $lower_file $upper_file"
  [ "$status" -eq 0 ]

  # Mount overlayfs at $merge_path.
  docker exec "$syscont" bash -c \
    "mount -t overlay overlay -olowerdir=$lower_path,upperdir=$upper_path,workdir=$work_path $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_mnt $syscont $merge_path

  # Verify dir/file content in merge folder is the expected one.
  docker exec "$syscont" stat $lower_dir $lower_file $upper_dir $upper_file
  [ "$status" -eq 0 ]

  # Remove existing upper dir.
  docker exec "$syscont" bash -c "rm -rf $merge_path/upper_dir"
  [ "$status" -eq 0 ]

  # Remove existing upper file.
  docker exec "$syscont" bash -c "rm -rf $merge_path/upper_file"
  [ "$status" -eq 0 ]

  # Confirm removed upper dir/file have been eliminated.
  docker exec "$syscont" bash -c "stat $merge_path/upper_dir || stat $merge_path/upper_file"
  [ "$status" -eq 1 ]

  # Remove existing lower dir.
  docker exec "$syscont" bash -c "rm -rf $merge_path/lower_dir"
  [ "$status" -eq 0 ]

  # Remove existing lower file.
  docker exec "$syscont" bash -c "rm -rf $merge_path/lower_file"
  [ "$status" -eq 0 ]

  # Confirm removed lower dir/file have been eliminated.
  docker exec "$syscont" bash -c "stat $merge_path/upper_dir || stat $merge_path/upper_file"
  [ "$status" -eq 1 ]

  # Verify 'whiteout' has been created for removed dir.
  docker exec "$syscont" bash -c "ls -l $upper_path/lower_dir"
  [ "$status" -eq 0 ]
  [[ $output =~ "c---------    1 root     root        0,   0".+"$upper_path/lower_dir" ]]

  # Verify 'whiteout' has been created for removed file.
  docker exec "$syscont" bash -c "ls -l $upper_path/lower_file"
  [ "$status" -eq 0 ]
  [[ $output =~ "c---------    1 root     root        0,   0".+"$upper_path/lower_file" ]]

  # Umount overlayfs mountpoint.
  docker exec "$syscont" bash -c "umount $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_umnt $syscont $merge_path

  docker_stop "$syscont"
}

# Mix of various overlayfs mounts and umounts operations from chroot'ed contexts,
# creation of whiteouts, etc -- fairly decent cocktail of ovfs mount instructions.
@test "mount overlayfs advanced ops" {

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec -d "$syscont" sh -c "docker pull quay.io/coreos/flannel:latest 2>&1"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

# Verify overlayfs mounts with relative paths.
@test "mount overlayfs relative paths" {

  local lower_path="$ovfs_path"/root/lower
  local upper_path="$ovfs_path"/root/upper
  local work_path="$ovfs_path"/root/work
  local merge_path="$ovfs_path"/root/merge

  local rel_lower_dir=root/lower
  local rel_upper_dir=root/upper
  local rel_work_dir=root/work
  local rel_merge_dir=root/merge

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c \
    "mkdir -p $lower_path $upper_path $work_path $merge_path"
  [ "$status" -eq 0 ]

  # Mount overlayfs making use of relative paths.
  docker exec "$syscont" bash -c \
    "cd $ovfs_path && \
    mount -t overlay overlay -olowerdir=$rel_lower_dir,upperdir=$rel_upper_dir,workdir=$rel_work_dir $rel_merge_dir"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_mnt $syscont $merge_path

  # Umount overlayfs mountpoint.
  docker exec "$syscont" bash -c "cd $ovfs_path && umount $rel_merge_dir"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_umnt $syscont $merge_path

  docker_stop "$syscont"
}

# Verify overlayfs mounts with various lower-layers.
@test "mount overlayfs multiple lower" {

  local lower_path_1="$ovfs_path"/root/lower1
  local lower_path_2="$ovfs_path"/root/lower2
  local lower_path_3="$ovfs_path"/root/lower3
  local upper_path="$ovfs_path"/root/upper
  local work_path="$ovfs_path"/root/work
  local merge_path="$ovfs_path"/root/merge

  local lower_dir_1="$ovfs_path"/root/lower1/lower_dir_1
  local lower_dir_2="$ovfs_path"/root/lower2/lower_dir_2
  local lower_dir_3="$ovfs_path"/root/lower3/lower_dir_3
  local lower_file_1="$ovfs_path"/root/lower1/lower_file_1
  local lower_file_2="$ovfs_path"/root/lower1/lower_file_2
  local lower_file_3="$ovfs_path"/root/lower1/lower_file_3
  local upper_dir="$ovfs_path"/root/upper/upper_dir
  local upper_file="$ovfs_path"/root/upper/upper_file

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" bash -c \
    "mkdir -p $lower_path_1 $lower_path_2 $lower_path_3 $upper_path $work_path $merge_path && \
     mkdir -p $lower_dir_1 $lower_dir_2 $lower_dir_3 $upper_dir && \
     touch $lower_file_1 $lower_file_2 $lower_file_3 $upper_file"
  [ "$status" -eq 0 ]

  # Mount overlayfs at $merge_path.
  docker exec "$syscont" bash -c \
    "mount -t overlay overlay -olowerdir=$lower_path_1:$lower_path_2:$lower_path_3,upperdir=$upper_path,workdir=$work_path $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_mnt $syscont $merge_path

  # Verify dir/file content in merge folder is the expected one.
  docker exec "$syscont" stat \
    $lower_dir_1 $lower_dir_2 $lower_dir_3 $lower_file_1 $lower_file_2 $lower_file_3 \
    $upper_dir $upper_file
  [ "$status" -eq 0 ]

  # Umount overlayfs mountpoint.
  docker exec "$syscont" bash -c "umount $merge_path"
  [ "$status" -eq 0 ]

  verify_syscont_overlay_umnt $syscont $merge_path

  docker_stop "$syscont"
}