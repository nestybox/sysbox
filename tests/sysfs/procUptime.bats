#!/usr/bin/env bats

#
# Testing of procUptime handler.
#

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
  # The debian bundle (not busybox) is used here because the rewind test
  # below needs perl to issue a real lseek() on an already-open fd.
  setup_debian

  # Obtain the container creation time.
  run cat /proc/uptime
  [ "$status" -eq 0 ]
  hostUptimeOutput="${lines[0]}"
  CNTR_START_TIMESTAMP=`echo ${hostUptimeOutput} | cut -d'.' -f 1`
}

function teardown() {
  teardown_debian syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "procUptime lookup() operation" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/uptime"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}

# Read operation.
@test "procUptime read() operation" {

  # Let's sleep a bit to obtain a meaningful (!= zero) uptime.
  sleep 3

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat /proc/uptime"
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

# Read operation on an already-open fd that is rewound with lseek(0).
#
# This is the libprocps access pattern: open /proc/uptime once, then seek
# back to zero before each sample. With FOPEN_NONSEEKABLE the seek failed
# with ESPIPE and every read after the first came back empty, so top
# reported "bad data in /proc/uptime" (sysbox issue #1045).
@test "procUptime read() operation after rewind" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont perl -e '
    open(my $fh, "<", "/proc/uptime") or die "open: $!";
    my $first = <$fh>;
    seek($fh, 0, 0) or die "seek: $!";
    my $second = <$fh>;
    chomp($first); chomp($second);
    print "$first;$second\n";'
  [ "$status" -eq 0 ]

  # Both samples must be complete uptime lines.
  local re='^[0-9]+\.[0-9]{2} [0-9]+\.[0-9]{2};[0-9]+\.[0-9]{2} [0-9]+\.[0-9]{2}$'
  [[ "${lines[0]}" =~ $re ]]
}
