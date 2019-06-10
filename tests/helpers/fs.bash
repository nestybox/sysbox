#!/bin/bash

#
# filesystem test helpers
#

# Given an 'ls -l' listing of a single file, verifies the permissions and ownership
function verify_perm_owner() {
  if [ "$#" -le 3 ]; then
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

  [[ "$perm" == "$want_perm" ]] && [[ "$uid" == "$want_uid" ]] && [[ "$gid" == "$want_gid" ]]
}

# Given an 'ls -l' listing of a single file, verifies it's read-only root:root
function verify_root_ro() {
  verify_perm_owner "-r--r--r--" "root" "root" "$@"
}

# Given an 'ls -l' listing of a single file, verifies it's read-write root:root
function verify_root_rw() {
  verify_perm_owner "-rw-r--r--" "root" "root" "$@"
}
