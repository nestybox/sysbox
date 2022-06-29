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

function checkSysboxDaemon() {
    local pidFile=$1
    local daemonPid=$2
    local pidFilePath=${sysboxRunDir}/${pidFile}

    if [ ! -f $pidFilePath ]; then
        return 1
    fi

    local pid=$(cat $pidFilePath)
    if [ -z $pid ]; then
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

    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-mgr pid file is properly generated and eliminated in scenarios
# where sysbox-mgr is gracefully shutdowned.
@test "sysbox-mgr graceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigterm to sysbox-mgr and verify that the old pid file is eliminated.
    # No changes are expected in sysbox-fs front.
    daemonStop "sysbox-mgr" "true"
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -ne 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Re-initialize sysbox-mgr and verify that a new pid file is generated.
    sysboxMgrStart
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-fs pid file is properly generated and eliminated in scenarios
# where sysbox-fs is gracefully shutdowned.
@test "sysbox-fs graceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigterm to sysbox-fs and verify that the old pid file is eliminated.
    # No changes are expected in sysbox-mgr front.
    daemonStop "sysbox-fs" "true"
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -ne 0 ]

    # Re-initialize sysbox-fs and verify that a new pid file is generated.
    sysboxFsStart
    local sysboxFsPid=$(pgrep sysbox-fs)
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-mgr pid file is properly generated and eliminated in scenarios
# where sysbox-mgr is ungracefully shutdowned.
@test "sysbox-mgr ungraceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigkill to sysbox-mgr and verify that the old pid file is still in place.
    # No changes are expected in sysbox-fs front.
    daemonStop "sysbox-mgr" "false"
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Re-initialize sysbox-mgr and verify that the old pid file has been overwritten
    # with the new pid value.
    sysboxMgrStart
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-fs pid file is properly generated and eliminated in scenarios
# where sysbox-fs is ungracefully shutdowned.
@test "sysbox-fs ungraceful restart" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Send sigkill to sysbox-fs and verify that the old pid file is still in place.
    # No changes are expected in sysbox-mgr front.
    daemonStop "sysbox-fs" "false"
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid ]
    [ "$status" -eq 0 ]

    # Re-initialize sysbox-fs and verify that the old pid file has been overwritten
    # with the new pid value.
    sysboxFsStart
    local sysboxFsPid=$(pgrep sysbox-fs)
    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]    
}

# Verify that sysbox-mgr process cannot be spawned multiple times.
@test "sysbox-mgr multi-instance overlap detection" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Attempt to initialize a second instance of sysbox-mgr and verify that this
    # is not allowed.
    sysboxMgrStart
    local newSysboxMgrPid=$(pgrep sysbox-mgr)
    run checkSysboxDaemon "sysmgr.pid" $newSysboxMgrPid
    [ "$status" -eq 0 ]
}

# Verify that sysbox-fs process cannot be spawned multiple times.
@test "sysbox-fs multi-instance overlap detection" {

    # Verify that sysbox daemons are running and that the corresponding pid
    # files are in place.
    local sysboxMgrPid=$(pgrep sysbox-mgr)
    local sysboxFsPid=$(pgrep sysbox-fs)

    run checkSysboxDaemon "sysmgr.pid" $sysboxMgrPid
    [ "$status" -eq 0 ]
    run checkSysboxDaemon "sysfs.pid" $sysboxFsPid
    [ "$status" -eq 0 ]

    # Attempt to initialize a second instance of sysbox-fs and verify that this
    # is not allowed.
    sysboxFsStart
    local newSysboxFsPid=$(pgrep sysbox-fs)
    run checkSysboxDaemon "sysfs.pid" $newSysboxFsPid
    [ "$status" -eq 0 ]
}
