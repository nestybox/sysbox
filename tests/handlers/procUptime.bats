# Testing of procUptime handler.

load ../helpers

# Container name.
SYSCONT_NAME=""

# Timestamps.
CNTR_START_TIMESTAMP=""

function setup_syscont() {
  run docker run --runtime=sysvisor-runc --rm -d --hostname syscont \
    nestybox/sys-container:debian-plus-docker tail -f /dev/null
  [ "$status" -eq 0 ]

  run docker ps --format "{{.ID}}"
  [ "$status" -eq 0 ]
  SYSCONT_NAME="$output"

  # Obtain the container creation time.
  run cat /proc/uptime
  [ "$status" -eq 0 ]
  hostUptimeOutput="${lines[0]}"
  CNTR_START_TIMESTAMP=`echo ${hostUptimeOutput} | cut -d'.' -f 1`
}

function teardown_syscont() {
  run docker stop "$SYSCONT_NAME"
}

function setup() {
  teardown_syscont
  setup_syscont
}

function teardown() {
  teardown_syscont
}

# Lookup/Getattr operation.
@test "procUptime lookup() operation" {
  run docker exec "$SYSCONT_NAME" sh -c \
    "ls -lrt /proc/uptime"
  [ "$status" -eq 0 ]

  # Read value should match this substring.
  [[ "${lines[0]}" =~ "-r--r--r-- 1 root root" ]]
}

# Read operation.
@test "procUptime read() operation" {

  # Let's sleep a bit to obtain a meaningful (!= zero) uptime.
  sleep 3

  run docker exec "$SYSCONT_NAME" sh -c \
    "cat /proc/uptime"
  [ "$status" -eq 0 ]

  # Obtain the container uptime and add it to the container creation time. This
  # combined value should be slightly lower than the system uptime.
  cntrUptimeOutput="${lines[0]}"
  cntrUptime=`echo ${cntrUptimeOutput} | cut -d'.' -f 1`
  cntrStartPlusUptime=$(($CNTR_START_TIMESTAMP + $cntrUptime))
  hostUptime=`cut -d'.' -f 1 /proc/uptime`

  echo "cntrStartPlusUptime = ${cntrStartPlusUptime}"
  echo "hostUptime = ${hostUptime}"
  [ $cntrStartPlusUptime -le $hostUptime ]
}
