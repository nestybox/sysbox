#!/usr/bin/env bats

#
# Test binfmt_misc inside Sysbox containers
#

load ../helpers/run
load ../helpers/docker
load ../helpers/environment
load ../helpers/sysbox-health
load ../helpers/multiarch

function setup() {
  if ! binfmt_misc_module_present; then
    skip "binfmt_misc module not present in kernel."
  fi

  if ! kernel_supports_binfmt_misc_namespacing; then
    skip "binfmt_misc not namespaced in kernel."
  fi

  # Ensure binfmt_misc is mounted on the host
  run mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
}

function teardown() {
  sysbox_log_check
}

@test "binfmt_misc auto mount" {
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # Verify binfmt_misc is mounted
  docker exec "$syscont" sh -c "mount | grep binfmt_misc"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "binfmt_misc on /proc/sys/fs/binfmt_misc type binfmt_misc" ]]

  # Verify binfmt_misc is enabled by default
  docker exec "$syscont" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  docker_stop "$syscont"
}

@test "binfmt_misc namespacing" {
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  # Disable binfmt_misc inside the container
  docker exec "$syscont" sh -c "echo 0 > /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "disabled" ]]

  # Verify that the host is not affected (confirms binfmt_misc is namespaced)
  run cat /proc/sys/fs/binfmt_misc/status
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  # Re-enable it in the container
  docker exec "$syscont" sh -c "echo 1 > /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  # Disable it on the host now
  run sh -c "echo 0 > /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]

  run cat /proc/sys/fs/binfmt_misc/status
  [ "$status" -eq 0 ]
  [[ "$output" == "disabled" ]]

  # Verify the container is not affected
  docker exec "$syscont" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  # Renable it on the host
  run sh -c "echo 1 > /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]

  run cat /proc/sys/fs/binfmt_misc/status
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  docker_stop "$syscont"
}

@test "binfmt_misc namespacing between container" {
  local syscont1=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local syscont2=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # Disable binfmt_misc inside the first container
  docker exec "$syscont1" sh -c "echo 0 > /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]

  docker exec "$syscont1" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "disabled" ]]

  # Verify the other container is unaffected
  docker exec "$syscont2" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  # Re-enable binfmt_misc in the first container
  docker exec "$syscont1" sh -c "echo 1 > /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]

  docker exec "$syscont1" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  # Disable binfmt_misc in the second container
  docker exec "$syscont2" sh -c "echo 0 > /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]

  docker exec "$syscont2" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "disabled" ]]

  # Verify the first container is unaffected
  docker exec "$syscont1" sh -c "cat /proc/sys/fs/binfmt_misc/status"
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]

  docker_stop "$syscont1"
  docker_stop "$syscont2"
}

@test "binfmt_misc register interpreter" {

  # create a simple interpreter
  tmpdir="/mnt/scratch/binfmt-test"
  mkdir -p ${tmpdir}

  cat << EOF > ${tmpdir}/test-interpreter
#!/bin/sh
echo "test interpreter called!"
EOF

  chmod +x ${tmpdir}/test-interpreter

  # start container and mount the test-intepreter to /usr/bin/test-interpreter
  local syscont1=$(docker_run --rm -v ${tmpdir}/test-interpreter:/usr/bin/test-interpreter ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # inside the container, register the interpreter with binfmt_misc for files with extension ".test"
  docker exec "$syscont1" sh -c 'echo ":test:E::test::/usr/bin/test-interpreter:" > /proc/sys/fs/binfmt_misc/register'
  [ "$status" -eq 0 ]

  # verify the registration worked
 docker exec "$syscont1" sh -c 'cat /proc/sys/fs/binfmt_misc/test | grep "extension .test"'
  [ "$status" -eq 0 ]

  # verify the interpreter works
  docker exec "$syscont1" sh -c "touch /root/file.test && chmod +x /root/file.test && /root/file.test"
  [ "$status" -eq 0 ]
  [[ "$output" == "test interpreter called!" ]]

  # start another container; verify interpreter does not work (because it's not registered within this container)
  local syscont2=$(docker_run --rm -v ${tmpdir}/test-interpreter:/usr/bin/test-interpreter ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont2" sh -c "touch /root/file.test && chmod +x /root/file.test && /root/file.test"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # same at host level (interpreter should not work)
  run sh -c "touch /root/file.test && chmod +x /root/file.test && /root/file.test"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # cleanup
  rm -rf /root/file.test
  rm -rf ${tmpdir}
  docker_stop "$syscont1"
  docker_stop "$syscont2"
}
