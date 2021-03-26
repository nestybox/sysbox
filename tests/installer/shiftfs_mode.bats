#!/usr/bin/env bats

# Basic tests for ...
#

load ../helpers/run
load ../helpers/docker
load ../helpers/fs
load ../helpers/sysbox-health
load ../helpers/installer


# First testcase must launch 'install_init' routine.
@test "no pre-existing dockerd config" {

  install_init

  docker_return_defaults

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check that no debconf question was asked.

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify
}

@test "pre-existing & unprocessed dockerd config: sysbox runtime" {

  docker_return_defaults

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

  install_sysbox

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify
}

@test "pre-existing & processed dockerd config: sysbox runtime" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/local/sbin/sysbox-runc"
        }
    }
}
EOF

  # Have docker absorve above config.
  run kill -SIGHUP $(pidof dockerd)
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify
}

@test "pre-existing & unprocessed dockerd config: non-sysbox runtime" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
	      "dummy-runc": {
		        "path": "/usr/local/sbin/dummy-runc"
	      },
	      "sysbox-runc": {
		        "path": "/usr/local/sbin/sysbox-runc"
	      }
    }
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Verify that the non-sysbox (dummy) runtime is left untouched in docker config.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq --exit-status '.runtimes | has(\"dummy-runc\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]

  uninstall_verify
}

@test "pre-existing & processed dockerd config: non-sysbox runtime" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
	      "dummy-runc": {
		        "path": "/usr/local/sbin/dummy-runc"
	      },
	      "sysbox-runc": {
		        "path": "/usr/local/sbin/sysbox-runc"
	      }
    }
}
EOF

  # Have docker absorve above config.
  run kill -SIGHUP $(pidof dockerd)
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Verify that the non-sysbox (dummy) runtime is left untouched in docker config.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq --exit-status '.runtimes | has(\"dummy-runc\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]

  uninstall_verify
}

# In 'shiftfs' nodes, verify that procesing a docker config with a userns entry,
# that has *not* been digested by dockerd, will not force the installer to change
# to 'userns-remap' mode. IOW, dockerd will continue operating in the same mode.
@test "pre-existing & unprocessed dockerd config: sysbox userns" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify
}

# In 'shiftfs' nodes, verify that procesing a docker config with a userns entry, that
# has already been digested by dockerd, will *not* force the installer to change to
# 'shiftfs' mode. IOW, dockerd will continue operatin in the same mode.
@test "pre-existing & processed dockerd config: sysbox userns" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  # Cold-boot dockerd to process above config.
  run systemctl restart docker
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence
  
  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in shiftfs mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify
}


# - Test with shiftfs and sysbox runtime already present in daemon.json
# - Test with shiftfs and a secondary runtime already present in daemon.json

# - Test with shiftfs module present but with userns-remap entry in dockerd config (yes to question)
# - Test with shiftfs module present but with userns-remap entry in dockerd config (no to question)
# - Test with shiftfs module present but with userns-remap entry in dockerd config (yes to question and containers alive)
# - Test with shiftfs module present but with userns-remap entry in dockerd config (no to question and containers alive)

# - Repeat all the above testcases but now w/o shiftfs being present.

# @test "kernel headers off" {
# skip
#   #kernel_headers_uninstall

#   install_sysbox

#   install_verify

#   run 

#   uninstall_sysbox purge

#   uninstall_verify

#   kernel_headers_install
# }
