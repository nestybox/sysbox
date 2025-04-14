#!/usr/bin/env bats

#
# Test docker DNS resolution in sys containers
#

load ../helpers/run
load ../helpers/net
load ../helpers/docker
load ../helpers/sysbox-health
load ../helpers/environment

export iface_mtu=$(egress_iface_mtu)

function teardown() {
  sysbox_log_check
}

@test "syscont dns (def bridge)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep nameserver /etc/resolv.conf"
  [ "$status" -eq 0 ]
  local syscont_dns=$output

  local host_dns=$(grep "nameserver" /etc/resolv.conf)

  # verify /etc/resolv.conf
  [[ "$syscont_dns" == "$host_dns" ]]

  # verify iptables are clean
  docker exec "$syscont" sh -c "ip -4 route show default | cut -d' ' -f3"
  [ "$status" -eq 0 ]
  local gateway=$output

  docker exec "$syscont" sh -c "iptables -t nat -L"
  [ "$status" -eq 0 ]
  local ip_tables=$output

  run sh -c "grep $gateway $ip_tables"
  [ "$status" -ne 0 ]

  # verify DNS resolution
  docker exec "$syscont" sh -c "dig google.com"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "syscont dns (user bridge)" {

  skip "Failing; needs debug (issue #929)"

  docker network create -o "com.docker.network.driver.mtu"="${iface_mtu}" usernet

  local syscont=$(docker_run --rm --net=usernet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep nameserver /etc/resolv.conf"
  [ "$status" -eq 0 ]
  local syscont_dns=$output

  docker exec "$syscont" sh -c "ip -4 route show default | cut -d' ' -f3"
  [ "$status" -eq 0 ]
  local gateway=$output

  local host_dns=$(grep "nameserver" /etc/resolv.conf)

  # verify /etc/resolv.conf
  [[ "$syscont_dns" =~ "$gateway" ]]
  [[ "$syscont_dns" != "$host_dns" ]]

  #
  # Verify firewall rules are the expected ones. Notice that this process depends
  # on the backend utilized by fwd: traditional iptables vs nftables.
  #

  local fwd_backend=$(fwd_backend_type)

  if [ "$fwd_backend" = "iptables" ]; then
     # Chains
     docker exec "$syscont" sh -c "iptables -t nat -n -L PREROUTING | grep DOCKER_OUTPUT | awk '{ print \$5 }'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     docker exec "$syscont" sh -c "iptables -t nat -n -L OUTPUT | grep DOCKER_OUTPUT | awk '{ print \$5 }'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     docker exec "$syscont" sh -c "iptables -t nat -n -L POSTROUTING | grep DOCKER_POSTROUTING | awk '{ print \$5 }'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     # DNAT
     docker exec "$syscont" sh -c "iptables -t nat -n -L DOCKER_OUTPUT | egrep \"DNAT.+tcp.+to:127.0.0.11\" | awk '{ print \$5 }'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     docker exec "$syscont" sh -c "iptables -t nat -n -L DOCKER_OUTPUT | egrep \"DNAT.+udp.+to:127.0.0.11\" | awk '{ print \$5 }'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     # SNAT
     docker exec "$syscont" sh -c "iptables -t nat -n -L DOCKER_POSTROUTING | egrep \"SNAT.+tcp.+127.0.0.11\" | grep -q \"to:${gateway}:53\""
     [ "$status" -eq 0 ]

     docker exec "$syscont" sh -c "iptables -t nat -n -L DOCKER_POSTROUTING | egrep \"SNAT.+udp.+127.0.0.11\" | grep -q \"to:${gateway}:53\""
     [ "$status" -eq 0 ]

  elif [ "$fwd_backend" = "nftables" ]; then
     # Chains
     docker exec "$syscont" sh -c "nft list chain nat PREROUTING | egrep DOCKER_OUTPUT | awk '{print \$3}'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     docker exec "$syscont" sh -c "nft list chain nat OUTPUT | egrep DOCKER_OUTPUT | awk '{print \$3}'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     docker exec "$syscont" sh -c "nft list chain nat POSTROUTING | egrep DOCKER_POSTROUTING | awk '{print \$3}'"
     [ "$status" -eq 0 ]
     [[ "$output" == "$gateway" ]]

     # DNAT
     docker exec "$syscont" sh -c "nft list chain nat DOCKER_OUTPUT | egrep -q \"ip daddr ${gateway} tcp|tcp ip daddr ${gateway}\""
     [ "$status" -eq 0 ]

     docker exec "$syscont" sh -c "nft list chain nat DOCKER_OUTPUT | egrep -q \"ip daddr ${gateway} udp|udp ip daddr ${gateway}\""
     [ "$status" -eq 0 ]

     # SNAT
     docker exec "$syscont" sh -c "nft list chain nat DOCKER_POSTROUTING | egrep -q \"ip saddr 127.0.0.11 tcp|tcp ip saddr 127.0.0.11\""
     [ "$status" -eq 0 ]

     docker exec "$syscont" sh -c "nft list chain nat DOCKER_POSTROUTING | egrep -q \"ip saddr 127.0.0.11 udp|udp ip saddr 127.0.0.11\""
     [ "$status" -eq 0 ]
  fi

  # verify DNS resolution

  docker exec "$syscont" sh -c "dig google.com"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  docker network rm usernet
}

@test "inner container dns (def bridge)" {

  # sys container on default docker bridge
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep nameserver /etc/resolv.conf"
  [ "$status" -eq 0 ]
  local syscont_dns=$output

  # start inner docker
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify DNS in inner container (on inner default bridge)
  docker exec "$syscont" sh -c "docker run -d --name inner ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"grep nameserver /etc/resolv.conf\""
  [ "$status" -eq 0 ]
  local inner_dns=$output

  [[ "$inner_dns" == "$syscont_dns" ]]

  # NOTE: on WSL hosts, tests hungs here (networking issue)
  docker exec "$syscont" sh -c "docker exec inner apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner host google.com"
  [ "$status" -eq 0 ]

  # verify DNS in inner container (on inner user-defined bridge)
  docker exec "$syscont" sh -c "docker network create inner-net"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name inner2 --net inner-net ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 sh -c \"grep nameserver /etc/resolv.conf | cut -d ' ' -f2\""
  [ "$status" -eq 0 ]
  local inner2_dns=$output

  [[ "$inner2_dns" == "127.0.0.11" ]]

  docker exec "$syscont" sh -c "docker exec inner2 apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 host google.com"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
}

@test "inner container dns (user bridge)" {

  skip "Failing; needs debug (issue #929)"

  # sys container on **user-defined** docker bridge
  docker network create -o "com.docker.network.driver.mtu"="${iface_mtu}" usernet

  local syscont=$(docker_run --rm --net usernet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep nameserver /etc/resolv.conf"
  [ "$status" -eq 0 ]
  local syscont_dns=$output

  # start inner docker
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify DNS in inner container (on inner default bridge)
  docker exec "$syscont" sh -c "docker run -d --name inner ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"grep nameserver /etc/resolv.conf\""
  [ "$status" -eq 0 ]
  local inner_dns=$output

  [[ "$inner_dns" == "$syscont_dns" ]]

  docker exec "$syscont" sh -c "docker exec inner apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner host google.com"
  [ "$status" -eq 0 ]

  # verify DNS in inner container (on inner user-defined bridge)
  docker exec "$syscont" sh -c "docker network create inner-net"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name inner2 --net inner-net ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 sh -c \"grep nameserver /etc/resolv.conf | cut -d ' ' -f2\""
  [ "$status" -eq 0 ]
  local inner2_dns=$output

  [[ "$inner2_dns" == "127.0.0.11" ]]

  docker exec "$syscont" sh -c "docker exec inner2 apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 host google.com"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
  docker network rm usernet
}

@test "syscont with custom dns" {

  local custom_dns="1.0.0.1"
  local syscont=$(docker_run --rm --dns $custom_dns ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep \"^nameserver\" /etc/resolv.conf | cut -d ' ' -f 2"
  [ "$status" -eq 0 ]
  local syscont_dns=$output

  # verify /etc/resolv.conf
  [[ "$syscont_dns" == "$custom_dns" ]]

  # verify iptables are clean
  docker exec "$syscont" sh -c "ip -4 route show default | cut -d' ' -f3"
  [ "$status" -eq 0 ]
  local gateway=$output

  docker exec "$syscont" sh -c "iptables -t nat -L"
  [ "$status" -eq 0 ]
  local ip_tables=$output

  run sh -c "grep $gateway $ip_tables"
  [ "$status" -ne 0 ]

  # verify DNS resolution
  docker exec "$syscont" sh -c "dig google.com"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "inner container dns (syscont custom dns)" {

  # sys container on default docker bridge
  local custom_dns="1.0.0.1"
  local syscont=$(docker_run --rm --dns=$custom_dns ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep nameserver /etc/resolv.conf"
  [ "$status" -eq 0 ]
  local syscont_dns="${lines[0]}"

  # start inner docker
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify DNS in inner container (on inner default bridge)
  docker exec "$syscont" sh -c "docker run -d --name inner ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"grep nameserver /etc/resolv.conf\""
  [ "$status" -eq 0 ]
  local inner_dns="${lines[0]}"

  [[ "$inner_dns" == "$syscont_dns" ]]

  docker exec "$syscont" sh -c "docker exec inner apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner host google.com"
  [ "$status" -eq 0 ]

  # verify DNS in inner container (on inner user-defined bridge)
  docker exec "$syscont" sh -c "docker network create inner-net"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name inner2 --net inner-net ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 sh -c \"grep nameserver /etc/resolv.conf | cut -d ' ' -f2\""
  [ "$status" -eq 0 ]
  local inner2_dns="${lines[0]}"

  [[ "$inner2_dns" == "127.0.0.11" ]]

  docker exec "$syscont" sh -c "docker exec inner2 apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 host google.com"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
}

@test "inner container custom dns" {

  # sys container on default docker bridge
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep nameserver /etc/resolv.conf"
  [ "$status" -eq 0 ]
  local syscont_dns="${lines[0]}"

  # start inner docker
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify DNS in inner container (launched with --dns)
  local inner_custom_dns="1.0.0.1"
  docker exec "$syscont" sh -c "docker run -d --name inner --dns $inner_custom_dns ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"grep nameserver /etc/resolv.conf | cut -d ' ' -f2\""
  [ "$status" -eq 0 ]
  local inner_dns="${lines[0]}"

  [[ "$inner_dns" == "$inner_custom_dns" ]]
  [[ "$inner_dns" != "$syscont_dns" ]]

  docker exec "$syscont" sh -c "docker exec inner apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner host google.com"
  [ "$status" -eq 0 ]

  # verify DNS in inner container (launched with --dns on a user-defined bridge)
  docker exec "$syscont" sh -c "docker network create inner-net"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name inner2 --net inner-net --dns $inner_custom_dns ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 sh -c \"grep nameserver /etc/resolv.conf | cut -d ' ' -f2\""
  [ "$status" -eq 0 ]
  local inner2_dns="${lines[0]}"

  [[ "$inner2_dns" == "127.0.0.11" ]]

  docker exec "$syscont" sh -c "docker exec inner2 apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 host google.com"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
}

@test "inner container custom dns (syscont user bridge)" {

  skip "Failing; needs debug (issue #929)"

  # sys container on **user-defined** docker bridge
  docker network create -o "com.docker.network.driver.mtu"="${iface_mtu}" usernet
  [ "$status" -eq 0 ]

  local syscont=$(docker_run --rm --net usernet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "grep nameserver /etc/resolv.conf"
  [ "$status" -eq 0 ]
  local syscont_dns="${lines[0]}"

  # start inner docker
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify DNS in inner container (launched with --dns)
  local inner_custom_dns="1.0.0.1"
  docker exec "$syscont" sh -c "docker run -d --name inner --dns $inner_custom_dns ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"grep nameserver /etc/resolv.conf | cut -d ' ' -f2\""
  [ "$status" -eq 0 ]
  local inner_dns="${lines[0]}"

  [[ "$inner_dns" == "$inner_custom_dns" ]]
  [[ "$inner_dns" != "$syscont_dns" ]]

  docker exec "$syscont" sh -c "docker exec inner apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner host google.com"
  [ "$status" -eq 0 ]

  # verify DNS in inner container (launched with --dns on a user-defined bridge)
  docker exec "$syscont" sh -c "docker network create inner-net"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run -d --name inner2 --net inner-net --dns $inner_custom_dns ${CTR_IMG_REPO}/alpine tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 sh -c \"grep nameserver /etc/resolv.conf | cut -d ' ' -f2\""
  [ "$status" -eq 0 ]
  local inner2_dns="${lines[0]}"

  [[ "$inner2_dns" == "127.0.0.11" ]]

  docker exec "$syscont" sh -c "docker exec inner2 apk add bind-tools"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner2 host google.com"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
  docker network rm usernet
}
