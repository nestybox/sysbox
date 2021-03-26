#!/usr/bin/env bats

# Basic tests for ...
#

load ../helpers/run
load ../helpers/docker
load ../helpers/fs
load ../helpers/sysbox-health

export test_dir="/tmp/installer/"
export test_image="busybox"
export test_container="$test_image"

export VERSION=$(egrep -m 1 "\[|\]" CHANGELOG.md | cut -d"[" -f2 | cut -d"]" -f1)
export IMAGE_BASE_DISTRO=$(lsb_release -ds | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
export IMAGE_BASE_RELEASE=$(lsb_release -cs)
export IMAGE_FILE_PATH="image/deb/debbuild/${IMAGE_BASE_DISTRO}-${IMAGE_BASE_RELEASE}"
export IMAGE_FILE_NAME="sysbox_${VERSION}-0.${IMAGE_BASE_DISTRO}-${IMAGE_BASE_RELEASE}_amd64.deb"

# Installation / Uninstallation output string.
export installation_output=""
export uninstallation_output=""

# Dockerd default configuration dir/file.
export dockerCfgDir="/etc/docker"
export dockerCfgFile="${dockerCfgDir}/daemon.json"

# Debconf files to hold desired pkg configuration.
export auto_dockerd_restart="${test_dir}/auto_dockerd_restart.debconf"
export manual_dockerd_restart="${test_dir}/manual_dockerd_restart.debconf"

#
# Auxiliary routines.
#

function init() {

  run mkdir -p "$test_dir"
  [ "$status" -eq 0 ]

  run rm -rf "$test_dir/*"
  [ "$status" -eq 0 ]

  # Create debconf file to set "automatic_dockerd_restart" mode.
  cat > "${auto_dockerd_restart}" <<EOF
sysbox	sysbox/docker_userns_autoconfig	boolean	true
EOF

  # Create debconf file to set "manual_dockerd_restart" mode.
  cat > "${manual_dockerd_restart}" <<EOF
sysbox	sysbox/docker_userns_autoconfig	boolean	false
EOF
}

function kernel_headers_install() {

  run sh -c "sudo apt-get update && sudo apt-get install -y linux-headers-$(uname -r)"
  [ "$status" -eq 0 ]
}

function kernel_headers_uninstall() {

  run sh -c "sudo apt purge -y linux-headers-$(uname -r)"
  [ "$status" -eq 0 ]
}

function sysbox_install() {

  run sudo DEBIAN_FRONTEND=noninteractive dpkg -i ${IMAGE_FILE_PATH}/${IMAGE_FILE_NAME}
  installation_output=$output
  [ "$status" -eq 0 ]

  # Some wiggle-room for processes to initialize.
  sleep 3
}

function sysbox_uninstall() {
  local purge

  if [[ $1 = "purge" ]]; then
    purge="--purge"
  fi

  run sudo DEBIAN_FRONTEND=noninteractive dpkg ${purge} sysbox
  uninstallation_output=$output
  [ "$status" -eq 0 ]
}

function verify_installation() {

  run sudo dpkg -s sysbox
  [ "$status" -eq 0 ]

  run sh -c "sudo systemctl status sysbox | egrep -q \"active \(exited\)\""
  echo "status = ${status}"
  echo "output = ${output}"
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

function verify_uninstallation() {

  run sudo dpkg -s sysbox
  [ "$status" -ne 0 ]

  run sh -c "sudo systemctl status sysbox | egrep -q \"active \(exited\)\""
  echo "status = ${status}"
  echo "output = ${output}"
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

function verify_runtime_config_adition() {

  # Verify that sysbox runtime has been properly configured.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq '.runtimes | has(\"sysbox-runc\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]

  run sh -c "docker info | egrep -q \"Runtimes:.*sysbox-runc\""
  [ "$status" -eq 0 ]
}

function verify_runtime_config_deletion() {

  # Verify that sysbox runtime entry has been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq --exit-status '.runtimes | has(\"sysbox-runc\")' ${dockerCfgFile}"
  [ "$status" -ne 0 ]
}

function config_automatic_restart() {
  local on=$1

  if [[ ${on} = "false" ]]; then
    sudo debconf-set-selections "${manual_dockerd_restart}"
  fi

  sudo debconf-set-selections "${auto_dockerd_restart}"
}

#
# Test-cases.
#

@test "no pre-existing dockerd config" {

  local dockerPid1=$(pidof dockerd)

  sysbox_install

  verify_installation

  # Check that no debconf question was asked.

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" = "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\"\""
  [ "$status" -ne 0 ]

  verify_runtime_config_adition

  sysbox_uninstall purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" = "${dockerPid2}" ]

  verify_runtime_config_deletion

  verify_uninstallation
}

@test "pre-existing dockerd config: sysbox runtime" {

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/local/sbin/sysbox-runc"
        }
    }
}
EOF

  local dockerPid1=$(pidof dockerd)

  sysbox_install

  verify_installation

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" = "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\"\""
  [ "$status" -ne 0 ]

  verify_runtime_config_adition

  sysbox_uninstall purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" = "${dockerPid2}" ]

  verify_runtime_config_deletion

  verify_uninstallation
}

@test "pre-existing dockerd config: non-sysbox runtime" {

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
	      "dummy-sysbox-runc": {
		        "path": "/usr/local/sbin/dummy-sysbox-runc"
	      },
	      "sysbox-runc": {
		        "path": "/usr/local/sbin/sysbox-runc"
	      }
    }
}
EOF

  local dockerPid1=$(pidof dockerd)

  sysbox_install

  verify_installation

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" = "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\"\""
  [ "$status" -ne 0 ]

  verify_runtime_config_adition

  sysbox_uninstall purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" = "${dockerPid2}" ]

  verify_runtime_config_deletion

  # Verify that the non-sysbox (dummy) runtime is left untouched in docker config.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq --exit-status '.runtimes | has(\"dummy-sysbox-runc\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]

  verify_uninstallation
}

# - Test with shiftfs and sysbox runtime already present in daemon.json
# - Test with shiftfs and a secondary runtime already present in daemon.json

# - Test with shiftfs module present but with userns-remap entry in dockerd config (yes to question)
# - Test with shiftfs module present but with userns-remap entry in dockerd config (no to question)
# - Test with shiftfs module present but with userns-remap entry in dockerd config (yes to question and containers alive)
# - Test with shiftfs module present but with userns-remap entry in dockerd config (no to question and containers alive)

# - Repeat all the above testcases but now w/o shiftfs being present.

@test "kernel headers off" {
skip
  #kernel_headers_uninstall

  sysbox_install

  verify_installation

  run 

  sysbox_uninstall purge

  verify_uninstallation

  kernel_headers_install
}

    # create_oci_bundle

    # ls /var/lib/sysboxfs | egrep -q "$test_container"
    # [ "$status" -eq 1 ]

    # run cd "$test_dir"/"$test_container"
    # [ "$status" -eq 0 ]

    # #
    # sv_runc run -d --console-socket $CONSOLE_SOCKET "$test_container"
    # [ "$status" -eq 0 ]

    # #
    # run ls /var/lib/sysboxfs | egrep -q "$test_container"
    # [ "$status" -eq 0 ]

