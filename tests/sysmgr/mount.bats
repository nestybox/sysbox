#!/usr/bin/env bats

#
# Verify sys container mounts setup by the sysbox-mgr
#

load ../helpers/run
load ../helpers/fs
load ../helpers/sysbox-health

# verify sys container has a mount for /lib/modules/<kernel>
@test "kernel lib-module mount" {

  local kernel_rel=$(uname -r)
  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "mount | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "/lib/modules/${kernel_rel} on /lib/modules/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
  else
    [[ "$output" =~ "on /lib/modules/${kernel_rel}".+"ro".+"relatime" ]]
  fi

  docker_stop "$syscont"
}

# Verify that Ubuntu sys container has kernel-headers in the expected path.
@test "kernel headers mounts (ubuntu)" {

  local kernel_rel=$(uname -r)
  local distro=$(get_host_distro)

  local syscont=$(docker_run --rm ubuntu:bionic tail -f /dev/null)

  # Expected behavior will vary depending on the linux-distro running on the
  # host (i.e. test-priv container).
  if [[ "${distro}" == "centos" ]] ||
      [[ "${distro}" == "fedora" ]] ||
      [[ "${distro}" == "redhat" ]]; then

      docker exec "$syscont" sh -c "mount | grep \"/usr/src/kernels/${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
         [[ "${lines[0]}" =~ "/usr/src/kernels/${kernel_rel} on /usr/src/kernels/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/kernels/${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that /usr/src/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created in ubuntu's kernel-headers expected path.
      docker exec "$syscont" sh -c "stat /usr/src/linux-headers-${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 0 ]

 else
      docker exec "$syscont" sh -c "mount | grep \"/usr/src/linux-headers-${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
         [[ "${lines[0]}" =~ "/usr/src/linux-headers-${kernel_rel} on /usr/src/linux-headers-${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/linux-headers-${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that no /usr/src/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created -- it's not needed in this case as sysbox-runc/mgr
      # already bind-mounts all the required paths.
      docker exec "$syscont" sh -c "stat /usr/src/linux-headers-${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 1 ]
  fi

  docker_stop "$syscont"
}

# Verify that Fedora sys container has kernel-headers in the expected path.
@test "kernel headers mounts (fedora)" {

  local kernel_rel=$(uname -r)
  local distro=$(get_host_distro)

  local syscont=$(docker_run --rm fedora:31 tail -f /dev/null)

  # Expected behavior will vary depending on the linux-distro running on the
  # host (i.e. test-priv container).
  if [[ "${distro}" == "centos" ]] ||
      [[ "${distro}" == "fedora" ]] ||
      [[ "${distro}" == "redhat" ]]; then

      docker exec "$syscont" sh -c "mount | grep \"/usr/src/kernels/${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
        [[ "${lines[0]}" =~ "/usr/src/kernels/${kernel_rel} on /usr/src/kernels/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/kernels/${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that no /usr/src/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created -- it's not needed in this case as sysbox-runc/mgr
      # already bind-mounts all the required paths.
      docker exec "$syscont" sh -c "stat /usr/src/linux-headers-${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 1 ]

 else
      docker exec "$syscont" sh -c "mount | grep \"/usr/src/linux-headers-${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
         [[ "${lines[0]}" =~ "/usr/src/linux-headers-${kernel_rel} on /usr/src/linux-headers-${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/linux-headers-${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that /usr/src/kernels/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created in fedora's kernel-headers expected path).
      docker exec "$syscont" sh -c "stat /usr/src/kernels/${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 0 ]
  fi

  docker_stop "$syscont"
}
