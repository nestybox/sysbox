#!/usr/bin/env bats

#
# Sysbox installer integration-tests for scenarios where 'shiftfs' kernel
# module is available.
#

load ../helpers/run
load ../helpers/docker
load ../helpers/fs
load ../helpers/sysbox-health
load ../helpers/installer


function teardown() {
  sysbox_log_check
}

#
# Testcase #1.
#
# Ensure that this testcase always execute as this one initializes the testing
# environment for this test-suite.
#
@test "[shiftfs] no pre-existing dockerd config" {

  install_init

  docker_return_defaults

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

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

  verify_shiftfs_mode

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #2.
#
@test "[shiftfs] pre-existing & unprocessed dockerd config (sysbox runtime)" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
        }
    }
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

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

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #3.
#
@test "[shiftfs] pre-existing & processed dockerd config (sysbox runtime)" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
        }
    }
}
EOF

  # Have docker absorve above config.
  run kill -SIGHUP $(pidof dockerd)
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

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

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #4.
#
@test "[shiftfs] pre-existing & unprocessed dockerd config (non-sysbox runtime)" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
	      "dummy-runc": {
		        "path": "/usr/bin/dummy-runc"
	      },
	      "sysbox-runc": {
		        "path": "/usr/bin/sysbox-runc"
	      }
    }
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

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

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #5.
#
@test "[shiftfs] pre-existing & processed dockerd config (non-sysbox runtime)" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "runtimes": {
	      "dummy-runc": {
		        "path": "/usr/bin/dummy-runc"
	      },
	      "sysbox-runc": {
		        "path": "/usr/bin/sysbox-runc"
	      }
    }
}
EOF

  # Have docker absorve above config.
  run kill -SIGHUP $(pidof dockerd)
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd related msg expected in shiftfs mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q -v \"\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

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

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #6.
#
# In 'shiftfs' nodes, verify that procesing a docker config with a userns entry,
# that has *not* been digested by dockerd, will not force the installer to change
# to 'userns-remap' mode. IOW, dockerd will continue operating in the same mode.
#
@test "[shiftfs] pre-existing & unprocessed dockerd config (sysbox userns)" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that the 'userns-remap' entry is eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

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

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #7.
#
# In 'shiftfs' nodes, verify that procesing a docker config with a userns entry, that
# has already been digested by dockerd, will *not* force the installer to change to
# 'shiftfs' mode. IOW, dockerd will continue operatin in the same mode.
@test "[shiftfs] pre-existing & processed dockerd config (sysbox userns)" {

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

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.  
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in 'shiftfs' mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #8.
#
# Repeat testcase #6 with 'manual' docker-restart, which should not differ from
# original testcase as 'manual' restart has no bearing on 'shiftfs' operating
# mode.
@test "[shiftfs] pre-existing & unprocessed dockerd config (sysbox userns) -- existing container" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  # Initialize a regular container.
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  # Expect installation to fail.
  install_sysbox 1

  # Verify installation was just partially completed.
  partial_install_verify

  # Let's stop/remove the existing containers and launch installation again.
  run docker rm alpine
  [ "$status" -eq 0 ]

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that the 'userns-remap' entry is eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

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

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

#
# Testcase #9.
#
# Repeat testcase #7 with 'manual' docker-restart, which should not differ from
# original testcase as 'manual' restart has no bearing on 'shiftfs' operating
# mode.
@test "[shiftfs] pre-existing & processed dockerd config (sysbox userns) -- existing container" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  # Cold-boot dockerd to process above config.
  run systemctl restart docker
  [ "$status" -eq 0 ]

  # Initialize a regular container.
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  # Expect installation to fail.
  install_sysbox 1

  # Verify installation was just partially completed.
  partial_install_verify

  # Let's stop/remove the existing containers and launch installation again.
  run docker rm alpine
  [ "$status" -eq 0 ]

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in 'shiftfs' mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

#
# Testcase #10.
#
# Repeat testcase #6 with 'manual' docker-restart, which should not differ from
# original testcase as 'manual' restart has no bearing on 'shiftfs' operating
# mode.
@test "[shiftfs] pre-existing & unprocessed dockerd config (sysbox userns) -- manual config" {

  docker_return_defaults

  config_automatic_userns_remap false

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must restart to process the network config changes. No changes are expected
  # in regards to 'userns-remap' mode coz existing 'userns' changes are just superficial
  # and also, 'shiftfs' module is present.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected while operating in 'shiftfs'
  # mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #11.
#
# Repeat testcase #7 with 'manual' docker-restart, which should not differ from
# original testcase as 'manual' restart has no bearing on 'shiftfs' operating
# mode.
@test "[shiftfs] pre-existing & processed dockerd config (sysbox userns) -- manual restart" {

  docker_return_defaults

  config_automatic_userns_remap false

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  # Cold-boot dockerd to process above config.
  run systemctl restart docker
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must restart to process the network config changes. Docker is already operating
  # in 'userns-remap' mode, so no config changes are expected in this front.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd didn't restart. No dockerd restart expected in 'shiftfs' mode.
  # No docker restart when operating in 'userns' mode and 'manual' configuration. Also
  # docker's network-config is left untouched, so no need to restart on that front either.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #12.
#
# Ensure that this testcase always execute as this one initializes the testing
# environment for this test-suite. See "Case 2)" in sysbox.config.
#
@test "[shiftfs] pre-existing dockerd config with all required elems" {

  docker_return_defaults

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "bip": "172.20.0.1/16",
    "default-address-pools": [
        {
            "base": "172.25.0.0/16",
            "size": 24
        }
    ]
}
EOF

  # Cold-boot dockerd to process above config.
  run systemctl restart docker
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check dockerd did **not** restart as docker's config already incorporates all
  # the attributes that are 'disruptive' and, thereby, require docker restart.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_shiftfs_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

  uninstall_sysbox purge

  # Check dockerd didn't restart as there are no disruptive changes to process
  # (i.e. network-config is untouched after restart).
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}