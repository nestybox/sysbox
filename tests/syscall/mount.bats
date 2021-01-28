#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls
#

load ../helpers/run
load ../helpers/syscall
load ../helpers/docker
load ../helpers/environment
load ../helpers/mounts
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

#
# Test to verify common mount syscall checks performed by sysbox
#

# Testcase #1.
#
# Verify that mount syscall emulation performs correct path resolution (per path_resolution(7))
@test "mount path-resolution" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  # TODO: test chmod dir permissions & path-resolution

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # absolute path
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative path
  docker exec "$syscont" bash -c "cd /root/l1 && mount -t proc proc l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # .. in path
  docker exec "$syscont" bash -c "cd /root/l1/l2 && mount -t proc proc ../../../root/l1/l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # . in path
  docker exec "$syscont" bash -c "cd /root/l1/l2 && mount -t proc proc ./proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cd $mnt_path && mount -t proc proc ."
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink
  docker exec "$syscont" bash -c "cd /root && ln -s l1/l2 l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc l2link/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink at end
  docker exec "$syscont" bash -c "cd /root && ln -s l1/l2/proc proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc proclink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # abs symlink
  docker exec "$syscont" bash -c "cd /root && ln -s /root/l1/l2/proc abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc abslink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # invalid path
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc invalidpath"
  [ "$status" -eq 255 ]
  [[ "$output" =~ "No such file or directory" ]]

  # TODO: overly long path (> MAXPATHLEN) returns in ENAMETOOLONG

  # TODO: mount syscall with empty mount path (should return ENOENT)
  # requires calling mount syscall directly

  docker_stop "$syscont"
}

# Testcase #2.
#
# Verify that mount syscall emulation does correct permission checks
@test "mount permission checking" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/debian:latest tail -f /dev/null)
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

# Testcase #3.
#
# Verify that mount syscall emulation does correct capability checks
@test "mount capability checking" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/debian:latest tail -f /dev/null)
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
