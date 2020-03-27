#!/bin/bash

#
# sysbox health checkers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

SYSBOX_MGR_NAME=sysbox-mgr
SYSBOX_MGR_LOG=/var/log/sysbox-mgr.log

SYSBOX_FS_NAME=sysbox-fs
SYSBOX_FS_LOG=/var/log/sysbox-fs.log

#
# sysbox-fs
#

function sysboxfs_log_check() {
  grep "ERRO" $SYSBOX_FS_LOG
  if [ $? -eq 0 ]; then
    return 1
  fi
  true
}

function sysboxfs_ps_check() {
  res=$(pgrep -P $(pidof $SYSBOX_FS_NAME))
  if [ $? -eq 0 ]; then
    return 1
  fi
  true
}

function sysboxfs_health_check() {

  if ! sysboxfs_log_check; then
    return 1
  fi

  if ! sysboxfs_ps_check; then
    return 1
  fi

  true
}

#
# sysbox-mgr
#

function sysboxmgr_log_check() {
  grep "ERRO" $SYSBOX_MGR_LOG
  if [ $? -eq 0 ]; then
    return 1
  fi
  true
}

function sysboxmgr_ps_check() {
  res=$(pgrep -P $(pidof $SYSBOX_MGR_NAME))
  if [ $? -eq 0 ]; then
    return 1
  fi
  true
}

function sysboxmgr_health_check() {

  if ! sysboxmgr_log_check; then
    return 1
  fi

  if ! sysboxmgr_ps_check; then
    return 1
  fi

  true
}

#
# sysbox
#

function sysbox_log_check() {

  if ! sysboxfs_log_check; then
    return 1
  fi

  if ! sysboxmgr_log_check; then
    return 1
  fi

  true
}

function sysbox_ps_check() {

  if ! sysboxfs_ps_check; then
    return 1
  fi

  if ! sysboxmgr_ps_check; then
    return 1
  fi

  true
}

function sysbox_health_check() {

  if ! sysboxfs_health_check; then
    return 1
  fi

  if ! sysboxmgr_health_check; then
    return 1
  fi

  true
}
