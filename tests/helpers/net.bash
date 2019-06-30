#!/bin/bash

# Given the output of "ip a" and an interface name, returns the IP address.
function parse_ip() {
  if [ $# -lt 2 ]; then
     return 1
  fi

  local ip_a_str="$1"
  local iface="$2"

  echo "$ip_a_str" | egrep "inet.+ $iface" | awk '{ print $2}' | awk '{split($0,a,"/"); print a[1]}'
}
