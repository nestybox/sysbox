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

# Given the output of "ip a" and an interface name, returns the IP subnet.
function parse_subnet() {
  if [ $# -lt 2 ]; then
     return 1
  fi

  local ip_a_str="$1"
  local iface="$2"

  cidr=$(echo "$ip_a_str" | egrep "inet.+ $iface" | awk '{ print $2}')
  ip=$(echo "$cidr" | awk '{split($0,a,"/"); print a[1]}')
  idx=$(echo "$cidr" | awk '{split($0,a,"/"); print a[2]}')
  mask=$(cdr2mask $idx)

  local IFS=.
  read -r i1 i2 i3 i4 <<< "$ip"
  read -r m1 m2 m3 m4 <<< "$mask"

  printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

# Converts an IP subnet mask to the CIDR index
# Borrowed from:
# https://stackoverflow.com/questions/20762575/explanation-of-convertor-of-cidr-to-netmask-in-linux-shell-netmask2cdir-and-cdir
function mask2cdr()
{
   # Assumes there's no "255." after a non-255 byte in the mask
   local x=${1##*255.}
   set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) ${x%%.*}
   x=${1%%$3*}
   echo $(( $2 + (${#x}/4) ))
}

# Converts a CIDR index to a subnet mask
# Borrowed from:
# https://stackoverflow.com/questions/20762575/explanation-of-convertor-of-cidr-to-netmask-in-linux-shell-netmask2cdir-and-cdir
function cdr2mask()
{
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift $1 || shift
   echo ${1-0}.${2-0}.${3-0}.${4-0}
}

# Identifies the system's firewall backend being utilized.
function fwd_backend_type()
{
    if iptables --version | egrep -q "nf_tables"; then
	echo "nftables"
    else
	echo "iptables"
    fi
}
