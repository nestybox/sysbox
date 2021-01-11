#!/bin/bash

#
# mount helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

. $(dirname ${BASH_SOURCE[0]})/run.bash

function list_container_mounts() {
  local sc=$1
  __docker exec "$sc" sh -c "mount | awk '{print \$3}' | grep -w -v \"/\""
}

function list_container_ro_mounts() {
  local sc=$1
  __docker exec "$sc" sh -c "mount | grep \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
}

function list_container_rw_mounts() {
  local sc=$1
  __docker exec "$sc" sh -c "mount | grep -v \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
}

function list_container_rw_dir_mounts() {
  local sc=$1
  __docker exec "$sc" sh -c \
  "list=\$(mount | grep -v \"ro,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
}

function list_container_null_mounts() {
  local sc=$1
  __docker exec "$sc" sh -c \
  "list=\$(cat /proc/self/mountinfo | grep \"/null\" | awk '{print \$5}'); for i in \$list; do echo \$i; done"
}

function list_container_tmpfs_mounts() {
  local sc=$1
  __docker exec "$sc" sh -c \
  "list=\$(cat /proc/self/mountinfo | grep \"tmpfs tmpfs\" | awk '{print \$5}'); for i in \$list; do echo \$i; done"
}
