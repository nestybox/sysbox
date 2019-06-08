#
# sysvisor-fs test helpers
#

# verifies the permissions of the given /proc file in the given container
function verify_proc_perm() {
  [[ "$#" = 3 ]]

  local container=$1
  local path=$2
  local want_perm=$3

  runc exec $container sh -c "ls -lrt $path"

  local perm=$(echo "${lines[0]}" | awk '{print $1}')
  local uid=$(echo "${lines[0]}" | awk '{print $3}')
  local gid=$(echo "${lines[0]}" | awk '{print $4}')

  [ "$perm" = "$want_perm" ]

  # /proc files are normally owned by root:root
  [ "$uid" = "root" ]
  [ "$gid" = "root" ]
}

# verifies the given /proc file in the given container are readonly
function verify_proc_ro() {
  [[ "$#" = 2 ]]
  local container=$1
  local path=$2
  verify_proc_perm $container $path "-r--r--r--"
}

# verifies the given /proc file in the given container are read-write by owner
function verify_proc_rw() {
  [[ "$#" = 2 ]]
  local container=$1
  local path=$2
  verify_proc_perm $container $path "-rw-r--r--"
}
