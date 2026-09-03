#!/usr/bin/env bats

#
# Integration test to verify the operation of the Sysbox's devManager features
# for the `/dev/net/tun` device interface.
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

sysbox_devices_host_path="/var/lib/sysbox/devices"

@test "devNetTun basic" {

  # Skip if /dev/net/tun is not present in the host.
  run sh -c "ls -l /dev/net/tun"
  if [ "$status" -ne 0 ]; then
    skip "/dev/net/tun not present in host"
  fi

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:jammy tail -f /dev/null)

  # Verify that the `/dev/net/tun` interface is placed at the expected path in the host.
  run sh -c "ls -l \${sysbox_devices_host_path}/\${syscont}/dev/net/tun"
  [ "$status" -eq 0 ]
  [[ $output == *"/dev/net/tun" ]]

  # Verify that the `/dev/net/tun` interface is bind-mounted into the sys container.
  docker exec "$syscont" sh -c "cat /proc/self/mountinfo | egrep -q \"/dev/net/tun /dev/net/tun rw\""
  [ "$status" -eq 0 ]

  # Verify that the `/dev/net/tun` interface is present in the sys container and with
  # the expected attributes (uid, gid, permissions, etc).
  docker exec "$syscont" sh -c "ls -l /dev/net/tun | egrep -q \"crw-rw-rw- 1 root root 10, 200\""
  [ "$status" -eq 0 ]
  
  # Install test/config tools.
  docker exec "$syscont" sh -c "apt-get update && apt-get install -y iproute2 uml-utilities iputils-ping"
  [ "$status" -eq 0 ]

  # Create a tun device.
  docker exec "$syscont" sh -c "tunctl -t tun0"
  [ "$status" -eq 0 ]

  # Verify that the tun device was created.
  docker exec "$syscont" sh -c "ip link show tun0"
  [ "$status" -eq 0 ]

  # Set an ip address to the tun device.
  docker exec "$syscont" sh -c "ip addr add 10.0.0.1/24 dev tun0"
  [ "$status" -eq 0 ]

  # Verify that the ip address was set.
  docker exec "$syscont" sh -c "ip addr show dev tun0 | egrep -q \"10.0.0.1\""
  [ "$status" -eq 0 ]

  # Verify network connectivity.
  docker exec "$syscont" sh -c "ping -c 1 10.0.0.1"
  [ "$status" -eq 0 ]

  # Delete ip address from the tun device.
  docker exec "$syscont" sh -c "ip addr del 10.0.0.1/24 dev tun0"
  [ "$status" -eq 0 ]

  # Remove the tun device.
  docker exec "$syscont" sh -c "tunctl -d tun0"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"

  # Verify that the tun device was removed from the host after the sys container is removed.  
  sleep 2
  run sh -c "ls ${sysbox_devices_host_path}/${syscont}"
  [ "$status" -ne 0 ]
}