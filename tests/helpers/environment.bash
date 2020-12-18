#!/bin/bash

#
# Environment specific routines.
#

# Dockerd default configuration dir/file.
export dockerCfgDir="/etc/docker"
export dockerCfgFile="${dockerCfgDir}/daemon.json"

# Default MTU value associated to egress-interface.
export default_mtu=1500

# Returns container's egress interface mtu.
function egress_iface_mtu() {

  if jq --exit-status 'has("mtu")' ${dockerCfgFile} >/dev/null; then
    local mtu=$(jq --exit-status '."mtu"' ${dockerCfgFile} 2>&1)

    if [ ! -z "$mtu" ] && [ "$mtu" -lt 1500 ]; then
      echo $mtu
    else
      echo $default_mtu
    fi
  else
    echo $default_mtu
  fi
}

function get_distro() {
   lsb_release -is | tr '[:upper:]' '[:lower:]'
}

function get_distro_release() {
   local distro=$(get_distro)

   if [[ ${distro} == centos || \
         ${distro} == redhat || \
         ${distro} == fedora ]]; then
      lsb_release -ds | tr -dc '0-9.' | cut -d'.' -f1
   else
      lsb_release -cs
   fi
}

function get_kernel_release() {
  uname -r
}
