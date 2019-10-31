#!/usr/bin/env bats

#
# Verify proper operation of a systemd within a sysbox container.
#

load ../../helpers/run

function wait_for_init() {
    #
    # For systemd to be deemed as fully initialized, we must have at least
    # these four processes running.
    #
    # admin@sys-cont:~$ ps -ef | grep systemd
    # root       273     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-journald
    # systemd+   481     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-resolved
    # message+   844     1  0 Oct22 ?        00:00:00 /usr/bin/dbus-daemon --system --systemd-activation
    # root       871     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-logind
    #
    retry 10 1 __docker exec "$SYSCONT_NAME" \
        sh -c "ps -ef | egrep systemd | wc -l | egrep [4-9]+"

    # And we also have to wait for systemd to initialize all other services
    sleep 3
}

function check_systemd_mounts() {
    #
    # Check that the following resources are properly mounted to satisfy systemd
    # requirements:
    #
    # - /run                tmpfs   tmpfs    rw
    # - /run/lock           tmpfs   tmpfs    rw
    # - /tmp                tmpfs   tmpfs    rw
    # - /sys/kernel/config  tmpfs   tmpfs    rw
    # - /sys/kernel/debug   tmpfs   tmpfs    rw
    #
    docker exec "$SYSCONT_NAME" sh -c \
        "findmnt | egrep -e \"\/run .*tmpfs.*rw\" \
                   -e \"\/run\/lock .*tmpfs.*rw\" \
                   -e \"\/tmp .*tmpfs.*rw\" \
                   -e \"\/sys\/kernel\/config.*tmpfs.*rw\" \
                   -e \"\/sys\/kernel\/debug.*tmpfs.*rw\" \
                   | wc -l | egrep -q 5"

    [ "$status" -eq 0 ]
}

@test "systemd basic features" {

    # Launch systemd container.
    SYSCONT_NAME=$(docker_run -d --rm --name=sys-cont-systemd \
        --hostname=sys-cont-systemd nestybox/ubuntu-bionic-systemd)

    wait_for_init

    # Verify that systemd has been properly initialized (no major errors observed).
    docker exec "$SYSCONT_NAME" sh -c "systemctl status"
    [ "$status" -eq 0 ]
    [[ "${lines[1]}" =~ "State: running" ]]

    # Verify that systemd's required resources are properly mounted.
    check_systemd_mounts

    # Verify that the hostname was properly set during container initialization,
    # which would confirm that 'hostnamectl' feature and its systemd dependencies
    # (i.e. dbus) are working as expected.
    docker exec "$SYSCONT_NAME" sh -c \
        "hostnamectl | egrep -q \"hostname: sys-cont-systemd\""
    [ "$status" -eq 0 ]

    # Restart a systemd service (journald) and verify it returns to 'running'
    # state.
    docker exec "$SYSCONT_NAME" sh -c \
        "systemctl status systemd-journald.service | egrep \"active \(running\)\""
    echo "status = ${status}"
    echo "output = ${output}"
    [ "$status" -eq 0 ]

    docker exec "$SYSCONT_NAME" systemctl restart systemd-journald.service
    echo "status = ${status}"
    echo "output = ${output}"
    [ "$status" -eq 0 ]

    sleep 2

    docker exec "$SYSCONT_NAME" sh -c \
        "systemctl status systemd-journald.service | egrep \"active \(running\)\""
    echo "status = ${status}"
    echo "output = ${output}"
    [ "$status" -eq 0 ]

    # Cleanup
    docker_stop "$SYSCONT_NAME"
    [ "$status" -eq 0 ]
}

@test "systemd mount overlaps" {

    # Launch systemd container.
    SYSCONT_NAME=$(docker_run -d --rm \
                    --mount type=tmpfs,destination=/run:ro \
                    --mount type=tmpfs,destination=/run/lock:ro \
                    --mount type=tmpfs,destination=/tmp:ro \
                    --mount type=tmpfs,destination=/sys/kernel/config:ro \
                    --mount type=tmpfs,destination=/sys/kernel/debug:ro \
                    --name=sys-cont-systemd \
                    --hostname=sys-cont-systemd nestybox/ubuntu-bionic-systemd)

    wait_for_init

    # Verify that systemd has been properly initialized (no major errors observed).
    docker exec "$SYSCONT_NAME" sh -c "systemctl status"
    [ "$status" -eq 0 ]
    [[ "${lines[1]}" =~ "State: running" ]]

    # Verify that mount overlaps have been identified and replaced as per systemd
    # demands.
    check_systemd_mounts

    # Cleanup
    docker_stop "$SYSCONT_NAME"
    [ "$status" -eq 0 ]
}
