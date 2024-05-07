# Testing of handler for /proc/sys/kernel/shm* files.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

# /proc/sys/kernel/shm* files
SHM_FILES="shmall shmmax shmmni"

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "/proc/sys/kernel/shm* lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  for file in $SHM_FILES; do
	  sv_runc exec syscont sh -c "ls -lrt /proc/sys/kernel/${file}"
	  [ "$status" -eq 0 ]
	  verify_root_rw "${output}"
  done
}

# Verify the /proc/sys/kernel/shm* files can be written and are namespaced
@test "/proc/sys/kernel/shm* writes" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  for file in $SHM_FILES; do
	  # Read the value in the host first
	  local orig_val=$(cat /proc/sys/kernel/${file})

	  # Write inside the container
	  sv_runc exec syscont sh -c "echo 1024 > /proc/sys/kernel/${file}"
	  [ "$status" -eq 0 ]

	  # Verify container write worked
	  sv_runc exec syscont sh -c "cat /proc/sys/kernel/${file}"
	  [ "$status" -eq 0 ]
	  [ "$output" = "1024" ]

	  # Read from the host, verify the value is unchanged (i.e., it only changes
	  # inside the container).
	  local new_val=$(cat /proc/sys/kernel/${file})
	  [[ "$new_val" == "$orig_val" ]]
  done
}
