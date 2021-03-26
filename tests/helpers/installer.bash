#!/bin/bash

#
# Sysbox Installer Test Helper Functions
# (for tests using bats)
#

export test_dir="/tmp/installer"
export test_image="busybox"
export test_container="$test_image"

# Installation / Uninstallation output string.
export installation_output=""
export uninstallation_output=""

# Dockerd default configuration dir/file.
export dockerCfgDir="/etc/docker"
export dockerCfgFile="${dockerCfgDir}/daemon.json"

# Debconf files to hold desired pkg configuration.
export auto_docker_userns_remap="${test_dir}/auto_docker_userns_remap.debconf"
export manual_docker_userns_remap="${test_dir}/manual_docker_userns_remap.debconf"

# Default MTU value associated to egress-interface.
export default_mtu=1500

# Temp file for jq write operations.
tmpfile="${test_dir}/installer-scr"


function install_init() {

  run mkdir -p "$test_dir"
  [ "$status" -eq 0 ]

  run rm -rf "$test_dir/*"
  [ "$status" -eq 0 ]

  wait_for_dockerd

  # Uninstall sysbox if present.
  uninstall_sysbox purge

  # Wipe all pre-existing containers and restart dockerd from a clean slate.
  run rm -rf ${dockerCfgFile}
  [ "$status" -eq 0 ]
  run sh -c "docker stop \$(docker ps -a -q) || true"
  [ "$status" -eq 0 ]
  run docker container prune -f
  [ "$status" -eq 0 ]
  run systemctl restart docker
  [ "$status" -eq 0 ]

  sleep 3

  # Create debconf file to set automatic "docker_userns_remap" mode.
  cat > "${auto_docker_userns_remap}" <<EOF
sysbox	sysbox/docker_userns_remap_autoconfig	boolean	true
EOF

  # Create debconf file to set "manual_docker_userns_remap" mode.
  cat > "${manual_docker_userns_remap}" <<EOF
sysbox	sysbox/docker_userns_remap_autoconfig	boolean	false
EOF
}

function docker_return_defaults() {

  if [ ! -f "${dockerCfgFile}" ]; then
    return
  fi

  run rm -rf ${dockerCfgFile}
  [ "$status" -eq 0 ]

  run systemctl restart docker
  [ "$status" -eq 0 ]
}

function docker_config_userns_mode() {

  if [ ! -f "${dockerCfgFile}" ]; then
    return
  fi

  # If no 'userns-remap' key-entry is present, or if its associated value
  # is empty, create a key and set its value to 'sysbox' user.
  if [ $(jq 'has("userns-remap")' ${dockerCfgFile}) = "false" ] ||
     [ $(jq '."userns-remap"' ${dockerCfgFile}) = "\"\"" ]; then

    jq --indent 4 '. + {"userns-remap": "sysbox"}' \
      ${dockerCfgFile} > ${tmpfile} && cp ${tmpfile} ${dockerCfgFile}
    [ "$status" -eq 0 ]

    systemctl restart docker
    [ "$status" -eq 0 ]

    systemctl restart sysbox
    [ "$status" -eq 0 ]
  fi
}

function kernel_headers_install() {

  run sh -c "sudo apt-get update && sudo apt-get install -y linux-headers-$(uname -r)"
  [ "$status" -eq 0 ]
}

function kernel_headers_uninstall() {

  run sh -c "sudo apt purge -y linux-headers-$(uname -r)"
  [ "$status" -eq 0 ]
}

function install_sysbox() {

  local expected_result=$1

  run sudo DEBIAN_FRONTEND=noninteractive dpkg -i ${SB_PACKAGE_FILE}
  echo "${outputt}"
  [ "$status" -eq "$expected_result" ]

  # Some wiggle-room for processes to initialize.
  sleep 3
}

function uninstall_sysbox() {
  local purge

  if [[ $1 = "purge" ]]; then
    purge="--purge"
  fi

  run sudo DEBIAN_FRONTEND=noninteractive dpkg ${purge} ${SB_PACKAGE}
  uninstallation_output="${output}"
  [ "$status" -eq 0 ]
}

function install_verify() {

  run sudo dpkg -s ${SB_PACKAGE}
  [ "$status" -eq 0 ]

  run sh -c "sudo systemctl status sysbox | egrep -q \"active \(running\)\""
  [ "$status" -eq 0 ]

  run sh -c "sudo systemctl status sysbox-mgr | egrep -q \"active \(running\)\""
  [ "$status" -eq 0 ]

  run sh -c "sudo systemctl status sysbox-fs | egrep -q \"active \(running\)\""
  [ "$status" -eq 0 ]

  run command -v sysbox-mgr
  [ "$status" -eq 0 ]

  run command -v sysbox-fs
  [ "$status" -eq 0 ]

  run command -v sysbox-runc
  [ "$status" -eq 0 ]
}

function uninstall_verify() {

  run sudo dpkg -s ${SB_PACKAGE}
  [ "$status" -ne 0 ]

  run sh -c "sudo systemctl status sysbox | egrep -q \"active \(running\)\""
  [ "$status" -ne 0 ]

  run sh -c "sudo systemctl status sysbox-mgr | egrep -q \"active \(running\)\""
  [ "$status" -ne 0 ]

  run sh -c "sudo systemctl status sysbox-fs | egrep -q \"active \(running\)\""
  [ "$status" -ne 0 ]

  run command -v sysbox-mgr
  [ "$status" -ne 0 ]

  run command -v sysbox-fs
  [ "$status" -ne 0 ]

  run command -v sysbox-runc
  [ "$status" -ne 0 ]
}

function partial_install_verify() {

  run command dpkg -s ${SB_PACKAGE}
  [[ "$output" =~ "install ok half-configured" ]]
  [ "$status" -eq 0 ]
}

function verify_docker_config_sysbox_runtime_presence() {

  # Verify that sysbox runtime has been properly configured.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq '.runtimes | has(\"sysbox-runc\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]

  # Also, ensure that no duplicated sysbox-runc entries exist in config.
  run sh -c "egrep ' +\"sysbox-runc\": {' ${dockerCfgFile} | wc -l | egrep -q 1"
  [ "$status" -eq 0 ]
}

function verify_docker_config_sysbox_runtime_absence() {

  # Verify that sysbox runtime entry has been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq --exit-status '.runtimes | has(\"sysbox-runc\")' ${dockerCfgFile}"
  [ "$status" -ne 0 ]
}

function verify_docker_sysbox_runtime_presence() {

  run sh -c "docker info | egrep -q \"Runtimes:.*sysbox-runc\""
  [ "$status" -eq 0 ]
}

function verify_docker_sysbox_runtime_absence() {

  run sh -c "docker info | egrep -q \"Runtimes:.*sysbox-runc\""
  [ "$status" -ne 0 ]
}

function verify_docker_bip_presence() {

  run sh -c "jq --exit-status 'has(\"bip\")' ${dockerCfgFile} &&
             jq --exit-status '.bip' ${dockerCfgFile} | egrep -q \"172.20.0.1/16\""
  [ "$status" -eq 0 ]
}

function verify_docker_bip_absence() {

  run sh -c "jq --exit-status 'has(\"bip\")' ${dockerCfgFile} ||
             jq --exit-status '.bip ${dockerCfgFile} | egrep -q \"172.20.0.1/16\""
  [ "$status" -ne 0 ]
}

function verify_docker_address_pool_presence() {

  run sh -c "jq --exit-status 'has(\"default-address-pools\")' ${dockerCfgFile} &&
              jq --exit-status '.\"default-address-pools\"[] | select(.\"base\" == \"172.25.0.0/16\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]
}

function verify_docker_address_pool_absence() {

  run sh -c "jq --exit-status 'has(\"default-address-pools\")' ${dockerCfgFile} ||
              jq --exit-status '.\"default-address-pools\"[] | select(.\"base\" == \"172.25.0.0/16\")' ${dockerCfgFile}"
  [ "$status" -ne 0 ]
}

function verify_shiftfs_mode() {

  run sh -c "docker info 2>&1 | egrep -q \"^  userns$\""
  [ "$status" -ne 0 ]
}

function verify_userns_mode() {

  # Docker's userns mode.
  run sh -c "docker info 2>&1 | egrep -q \"^  userns$\""
  [ "$status" -eq 0 ]
}

function config_automatic_userns_remap() {
  local on=$1

  if [ ${on} = "false" ]; then
    sudo debconf-set-selections "${manual_docker_userns_remap}"
    return
  fi

  sudo debconf-set-selections "${auto_docker_userns_remap}"
}

function enable_shiftfs() {

  run modprobe shiftfs
  [ "$status" -eq 0 ]
}

function disable_shiftfs() {

  if ! lsmod | egrep -q "shiftfs"; then
    return
  fi

  run modprobe -r shiftfs
  [ "$status" -eq 0 ]

  run sh -c "lsmod | egrep -q \"shiftfs\""
  [ "$status" -eq 1 ]
}

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
