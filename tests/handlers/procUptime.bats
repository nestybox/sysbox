# Testing of procUptime handler.

load ../helpers

function setup() {
  setup_syscont

  # Obtain the container creation time.
  run cat /proc/uptime
  [ "$status" -eq 0 ]
  hostUptimeOutput="${lines[0]}"
  CNTR_START_TIMESTAMP=`echo ${hostUptimeOutput} | cut -d'.' -f 1`
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
