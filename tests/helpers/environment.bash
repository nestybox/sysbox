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