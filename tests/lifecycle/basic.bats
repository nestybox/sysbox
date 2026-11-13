#!/usr/bin/env bats

#
# Basic tests to asses the proper behavior of Sysbox daemon's initialization
# logic during graceful and ungraceful shutdown events.
#

load ../helpers/run
load ../helpers/sysbox-health

export sysboxRunDir="/run/sysbox"

function teardown() {
  sysbox_log_check
}

# In installer mode (SB_INSTALLER) sysbox-mgr and sysbox-fs run as systemd
# units. sysbox.service is BindsTo= both of them and both are PartOf= it, so
# stopping or killing either daemon makes systemd stop the other one too.
#
# Most of the tests below exercise the daemons' own pid-file and overlap
# detection logic, which does not depend on who supervises them. To keep that
# logic observable, they detach the daemons from systemd and drive them
# directly. The tests whose description starts with "systemd:" exercise the
# units instead, and the last one checks that systemd is back in charge.

# Returns 0 if any of the sysbox systemd units is active.
function sysboxUnitsActive() {
    systemctl is-active --quiet sysbox.service sysbox-mgr.service sysbox-fs.service
}

# Waits (up to 15 seconds) until no sysbox daemon is running.
function waitDaemonsGone() {
    local i
    for i in $(seq 1 15); do
        if ! pgrep sysbox-mgr >/dev/null && ! pgrep sysbox-fs >/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Waits (up to 20 seconds) until both daemons are running and have written
# their pid files.
function waitDaemonsUp() {
    local i
    for i in $(seq 1 20); do
        if pgrep sysbox-mgr >/dev/null && pgrep sysbox-fs >/dev/null &&
           [ -f ${sysboxRunDir}/sysmgr.pid ] && [ -f ${sysboxRunDir}/sysfs.pid ]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Leaves both daemons running outside of systemd, whatever state a previous
# test left them in.
function ensureDaemonsRunning() {
    if [ -n "$SB_INSTALLER" ] && sysboxUnitsActive; then
        systemctl stop sysbox.service sysbox-mgr.service sysbox-fs.service
        waitDaemonsGone
    fi

    pgrep sysbox-mgr >/dev/null || sysboxMgrStart
    pgrep sysbox-fs >/dev/null || sysboxFsStart
    waitDaemonsUp
}

# Leaves both daemons running under systemd, whatever state a previous test
# left them in.
function ensureSystemdRunning() {
    if ! pgrep sysbox-mgr >/dev/null || ! pgrep sysbox-fs >/dev/null ||
       ! sysboxUnitsActive; then
        pkill sysbox-mgr
        pkill sysbox-fs
        waitDaemonsGone
        systemctl start sysbox.service
        waitDaemonsUp
    fi
}

function setup() {
    if [[ "$BATS_TEST_DESCRIPTION" == systemd:* ]]; then
        [ -n "$SB_INSTALLER" ] || skip "sysbox daemons are not managed by systemd"
        ensureSystemdRunning
    else
        ensureDaemonsRunning
    fi
}

function checkSysboxPidFile() {
    local pidFile=$1
    local daemonPid=$2
    local pidFilePath=${sysboxRunDir}/${pidFile}

    if [ ! -f $pidFilePath ]; then
        return 1
    fi

    local pid=$(cat $pidFilePath)
    if [ -z $pid ] || [ "$pid" -ne "$daemonPid" ]; then
        return 1
    fi

    return 0
}

function daemonStop() {
    local daemon=$1
    local graceful=$2

    if [[ "$graceful" == "true" ]]; then
        pkill $daemon
    else
        pkill -9 $daemon
    fi

    sleep 2
}

function sysboxMgrStart() {
    bats_bg sysbox-mgr --log /var/log/sysbox-mgr.log &

    sleep 1
}

function sysboxFsStart() {
    bats_bg sysbox-fs --ignore-handler-errors --log /var/log/sysbox-fs.log &

    sleep 1
}

# Verify proper operation of pid files in steady-state.
@test "basic initialization -- steady state" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-mgr pid file is properly generated and eliminated in scenarios
# where sysbox-mgr is gracefully shutdown.
@test "sysbox-mgr graceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigterm to sysbox-mgr and verify that the old pid file is eliminated.
    # No changes are expected in sysbox-fs front.
    daemonStop "sysbox-mgr" "true"
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -ne 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Re-initialize sysbox-mgr and verify that a new pid file is generated.
    sysboxMgrStart
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-fs pid file is properly generated and eliminated in scenarios
# where sysbox-fs is gracefully shutdown.
@test "sysbox-fs graceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigterm to sysbox-fs and verify that the old pid file is eliminated.
    # No changes are expected in sysbox-mgr front.
    daemonStop "sysbox-fs" "true"
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -ne 0 ]

    # Re-initialize sysbox-fs and verify that a new pid file is generated.
    sysboxFsStart
    local sysboxFsPid=$(pgrep sysbox-fs)
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-mgr pid file is properly generated and eliminated in scenarios
# where sysbox-mgr is ungracefully shutdowned.
@test "sysbox-mgr ungraceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigkill to sysbox-mgr and verify that the old pid file is still in place.
    # No changes are expected in sysbox-fs front.
    daemonStop "sysbox-mgr" "false"
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Re-initialize sysbox-mgr and verify that the old pid file has been overwritten
    # with the new pid value.
    sysboxMgrStart
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-fs pid file is properly generated and eliminated in scenarios
# where sysbox-fs is ungracefully shutdown.
@test "sysbox-fs ungraceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigkill to sysbox-fs and verify that the old pid file is still in place.
    # No changes are expected in sysbox-mgr front.
    daemonStop "sysbox-fs" "false"
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Re-initialize sysbox-fs and verify that the old pid file has been overwritten
    # with the new pid value.
    sysboxFsStart
    local sysboxFsPid=$(pgrep sysbox-fs)
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]    
}

# Verify that sysbox-mgr process cannot be spawned multiple times.
@test "sysbox-mgr multi-instance overlap detection" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Attempt to initialize a second instance of sysbox-mgr and verify that this
    # is not allowed.
    sysboxMgrStart
    local newSysboxMgrPid=$(pgrep sysbox-mgr)
    run checkSysboxPidFile "sysmgr.pid" $newSysboxMgrPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-fs process cannot be spawned multiple times.
@test "sysbox-fs multi-instance overlap detection" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Attempt to initialize a second instance of sysbox-fs and verify that this
    # is not allowed.
    sysboxFsStart
    local newSysboxFsPid=$(pgrep sysbox-fs)
    run checkSysboxPidFile "sysfs.pid" $newSysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that restarting the sysbox service renews both daemons and their pid
# files.
@test "systemd: sysbox.service restart renews the daemons" {

    local oldMgrPid=$(pgrep sysbox-mgr)
    local oldFsPid=$(pgrep sysbox-fs)

    run systemctl restart sysbox.service
    [ "$status" -eq 0 ]
    run waitDaemonsUp
    [ "$status" -eq 0 ]

    local newMgrPid=$(pgrep sysbox-mgr)
    local newFsPid=$(pgrep sysbox-fs)
    [ "$newMgrPid" != "$oldMgrPid" ]
    [ "$newFsPid" != "$oldFsPid" ]

    run checkSysboxPidFile "sysmgr.pid" $newMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $newFsPid
    [ "$status" -eq 0 ]
}

# Verify that systemd takes the whole sysbox service down when one of the
# daemons dies, and that starting the service again brings both back with
# fresh pid files.
@test "systemd: a killed daemon takes sysbox.service down and it recovers" {

    local oldMgrPid=$(pgrep sysbox-mgr)

    pkill -9 sysbox-mgr

    # sysbox.service is BindsTo= the daemons: both daemons must go away.
    run waitDaemonsGone
    [ "$status" -eq 0 ]
    run sysboxUnitsActive
    [ "$status" -ne 0 ]

    run systemctl start sysbox.service
    [ "$status" -eq 0 ]
    run waitDaemonsUp
    [ "$status" -eq 0 ]

    local newMgrPid=$(pgrep sysbox-mgr)
    local newFsPid=$(pgrep sysbox-fs)
    [ "$newMgrPid" != "$oldMgrPid" ]
    run checkSysboxPidFile "sysmgr.pid" $newMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $newFsPid
    [ "$status" -eq 0 ]
}

# Verify that, at the end, systemd supervises both daemons again, leaving the
# system as it was found.
@test "systemd: sysbox daemons are supervised by systemd at the end" {

    run sysboxUnitsActive
    [ "$status" -eq 0 ]

    for unit in sysbox.service sysbox-mgr.service sysbox-fs.service; do
        run systemctl is-active $unit
        [ "$output" = "active" ]
    done

    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)
    run checkSysboxPidFile "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxPidFile "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}
