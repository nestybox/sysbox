#!/bin/bash

#
# sysbox health checkers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

SYSBOX_MGR_NAME=sysbox-mgr
SYSBOX_MGR_LOG=/var/log/sysbox-mgr.log
SYSBOX_MGR_MAX_FDS=30

SYSBOX_FS_NAME=sysbox-fs
SYSBOX_FS_LOG=/var/log/sysbox-fs.log

GREP_CTX_LINES=10

#
# sysbox-fs
#

function sysboxfs_log_check() {
  local ret

  ret=$(grep -C $GREP_CTX_LINES "level=error" $SYSBOX_FS_LOG)
  if [ $? -eq 0 ]; then
    printf "sysbox-fs log has errors:\n $ret"
    return 1
  fi
  return 0
}

function sysboxfs_ps_check() {
  # verify sysbox-fs is alive
  local ret

  ret=$(pidof $SYSBOX_FS_NAME > /dev/null)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs pid not found!"
    return 1
  fi

  # verify sysbox-fs has no child processes
  ret=$(pgrep -P $(pidof $SYSBOX_FS_NAME))
  if [ $? -eq 0 ]; then
    printf "sysbox-fs has unexpected child processes:\n $ret"
    return 1
  fi

  return 0
}

function sysboxfs_mnt_check() {
  # verify there are no sysbox-fs mounts
  local ret

  ret=$(mount | grep "/var/lib/sysboxfs")
  if [ $? -ne 1 ]; then
    printf "sysbox-fs has unexpected mounts:\n $ret"
    return 1
  fi

  return 0
}

function sysboxfs_health_check() {
  local ret

  ret=$(sysboxfs_log_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs log check failed:\n $ret\n"
    return 1
  fi

  ret=$(sysboxfs_ps_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs ps check failed:\n $ret\n"
    return 1
  fi

  ret=$(sysboxfs_mnt_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs mount check failed:\n $ret\n"
    return 1
  fi

  return 0
}

#
# sysbox-mgr
#

function sysboxmgr_log_check() {
  local ret

  ret=$(grep -C $GREP_CTX_LINES "level=error" $SYSBOX_MGR_LOG)
  if [ $? -eq 0 ]; then
    printf "sysbox-mgr log has errors:\n $ret"
    return 1
  fi

  return 0
}

function sysboxmgr_ps_check() {
  # verify sysbox-mgr is alive
  local ret

  ret=$(pidof $SYSBOX_MGR_NAME > /dev/null)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr pid not found!"
    return 1
  fi

  # verify sysbox-mgr has no child processes
  ret=$(pgrep -P $(pidof $SYSBOX_MGR_NAME))
  if [ $? -eq 0 ]; then
    printf "sysbox-mgr has unexpected child processes:\n $ret"
    return 1
  fi

  return 0
}

function sysboxmgr_fd_check() {
  # verify sysbox-mgr is not leaking file descriptors
  local num_fds

  num_fds=$(lsof -p $(pidof sysbox-mgr) 2>/dev/null | wc -l)
  if [ $num_fds -gt $SYSBOX_MGR_MAX_FDS ]; then
    output=$(lsof -p $(pidof sysbox-mgr) 2>/dev/null)
    printf "sysbox-mgr has $num_fds (> $SYSBOX_MGR_MAX_FDS) files opened:\n $output"
    return 1
  fi

  return 0
}

function sysboxmgr_health_check() {
  local ret

  ret=$(sysboxmgr_log_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr log check failed:\n $ret\n"
    return 1
  fi

  ret=$(sysboxmgr_ps_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr ps check failed:\n $ret\n"
    return 1
  fi

  ret=$(sysboxmgr_fd_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr fd check failed:\n $ret\n"
    return 1
  fi

  return 0
}

#
# sysbox
#

function sysbox_log_check() {
  local ret

  ret=$(sysboxfs_log_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs log check failed: $ret\n"
    return 1
  fi

  ret=$(sysboxmgr_log_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr log check failed: $ret\n"
    return 1
  fi

  return 0
}

function sysbox_ps_check() {
  local ret

  ret=$(sysboxfs_ps_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs ps check failed: $ret\n"
    return 1
  fi

  ret=$(sysboxmgr_ps_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr ps check failed: $ret\n"
    return 1
  fi

  return 0
}

function sysbox_mnt_check() {
  local ret

  ret=$(sysboxfs_mnt_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs mount check failed: $ret\n"
    return 1
  fi

  return 0
}

function sysbox_fd_check() {
  local ret

  ret=$(sysboxmgr_fd_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr fd check failed: $ret\n"
    return 1
  fi

  return 0
}

function sysbox_health_check() {
  local ret

  ret=$(sysboxfs_health_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-fs health check failed: $ret\n"
    return 1
  fi

  ret=$(sysboxmgr_health_check)
  if [ $? -ne 0 ]; then
    printf "sysbox-mgr health check failed: $ret\n"
    return 1
  fi

  return 0
}
