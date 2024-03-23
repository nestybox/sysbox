#!/usr/bin/env bats

#
# Tests that i386 applications can be executed on amd64 systems using multilib
#

load ../helpers/run
load ../helpers/docker
load ../helpers/environment
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "i386 application in amd64 system using multilib (sysbox issue 350)" {

  # This tests compiles an i386 C-application and runs it on an amd64 system
  # using the multilib feature of gcc. This is a test for sysbox issue 350.

  # this test is only valid on amd64 systems
  if [[ $(get_platform) != "amd64" ]]; then
    skip "multilib testcase supported only in amd64 architecture"
  fi

  # launch sys container
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  # install multilib support inside the container
  docker exec "$syscont" bash -c "apt-get update && apt-get install --no-install-recommends -y gcc-multilib"
  [ "$status" -eq 0 ]

  # compile an application for i386 / 32bit, compile flag m32 is used
  docker exec "$syscont" bash -c "echo 'int main(){return 0;}' | gcc -m32 -o test-i386 -xc -"
  [ "$status" -eq 0 ]

  # run the application
  docker exec "$syscont" bash -c "./test-i386"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
}
