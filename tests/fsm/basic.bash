#!/usr/bin/env bats

# Basic tests for ...
#

load ../helpers/run
load ../helpers/docker
load ../helpers/k8s
load ../helpers/fs
load ../helpers/sysbox-health

export test_dir="/tmp/fsm-test/"
export test_image="busybox"
export test_container="$test_image"

function create_test_dir() {
  run mkdir -p "$test_dir"
  [ "$status" -eq 0 ]

  run rm -rf "$test_dir/*"
  [ "$status" -eq 0 ]
}

function create_oci_bundle() {

    create_test_dir

    run mkdir -p "$test_dir"/"$test_container"/rootfs
    [ "$status" -eq 0 ]
    
    run cd "$test_dir"/"$test_container"
    [ "$status" -eq 0 ]    
    
    #run mkdir -p rootfs
    #[ "$status" -eq 0 ]

    #run docker export $(docker create \"$test_image\":latest) | tar -C rootfs -xvf -
    docker export \"$(docker create busybox:latest)\" | tar -C rootfs -xvf -
    [ "$status" -eq 0 ]
}

@test "container creation" {

    create_oci_bundle

    ls /var/lib/sysboxfs | egrep -q "$test_container"
    [ "$status" -eq 1 ]

    run cd "$test_dir"/"$test_container"
    [ "$status" -eq 0 ]

    #
    sv_runc run -d --console-socket $CONSOLE_SOCKET "$test_container"
    [ "$status" -eq 0 ]

    #
    run ls /var/lib/sysboxfs | egrep -q "$test_container"
    [ "$status" -eq 0 ]
}