# Testing of handler for /proc/sys/kernel/random

load ../helpers/fs
load ../helpers/run
load ../helpers/uuid
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

@test "/proc/sys/kernel/random/uuid lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -lrt /proc/sys/kernel/random/uuid"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}

@test "/proc/sys/kernel/random/uuid read" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat /proc/sys/kernel/random/uuid"
  [ "$status" -eq 0 ]

  is_valid_uuid "$output"
}

@test "/proc/sys/kernel/random/uuid read unique each time" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  declare -A uuid_map

  for i in $(seq 1 10); do
    sv_runc exec syscont sh -c "cat /proc/sys/kernel/random/uuid"
    [ "$status" -eq 0 ]

    uuid=$output
    is_valid_uuid "$uuid"

    # check we haven't seen this uuid before
    [[ -z ${uuid_map[$uuid]} ]]

    uuid_map[$uuid]=1
  done
}

@test "/proc/sys/kernel/random/uuid write" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "echo 0 > /proc/sys/kernel/random/uuid"
  [ "$status" -ne 0 ]
}

@test "/proc/sys/kernel/random dir" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # check number of files in the container's /proc/sys/kernel/random matches host
  sv_runc exec syscont sh -c "ls -l /proc/sys/kernel/random/uuid | wc -l"
  [ "$status" -eq 0 ]
  cnum=$output
  hnum=$(ls -l /proc/sys/kernel/random/uuid | wc -l)
  [ $cnum -eq $hnum ]

  # read from each of the files in /proc/sys/kernel/random (except uuid), and
  # compare the one in the host to the corresponding one in the container.
  for file in /proc/sys/kernel/random/*; do
    if [[ $(basename "$file") == "uuid" ]]; then
      continue
    fi

    if [[ -r "$file" ]]; then
      hfile=$(cat "$file")

      sv_runc exec syscont sh -c "cat $file"
      [ "$status" -eq 0 ]
      cfile=$output

      echo "hfile = $hfile"
      echo "cfile = $cfile"

      [[ "$hfile" == "$cfile" ]]
    fi
  done

  # check that writes to files in /proc/sys/kernel/random (except uuid) fail
  # with EPERM.
  for file in /proc/sys/kernel/random/*; do
    if [[ $(basename "$file") == "uuid" ]]; then
      continue
    fi
    sv_runc exec syscont sh -c "echo 0 > $file"
    [ "$status" -ne 0 ]
  done

}
