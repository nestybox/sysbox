#!/usr/bin/env bats

#
# Sysbox installer integration-tests for scenarios where 'shiftfs' kernel
# module is not available, and Docker must operat in 'userns-remap' mode.
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
@test "[userns] no pre-existing dockerd config -- automatic config" {

  install_init

  docker_return_defaults

  config_automatic_userns_remap true

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode. Also, we
  # would restart anyways to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'userns' to 'shiftfs' mode, as
  # that's what we do by default if no cntr is around.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify
}

#
# Testcase #2.
#
@test "[userns] pre-existing & unprocessed dockerd config (sysbox runtime) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

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

  install_sysbox 0

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode. Also, we
  # would restart anyways to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'userns' to 'shiftfs' mode, as
  # that's what we do by default if no cntr is around.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify
}

#
# Testcase #3.
#
@test "[userns] pre-existing & processed dockerd config (sysbox runtime) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

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

  install_sysbox 0

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode. Also, we
  # would restart anyways to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'userns' to 'shiftfs' mode, as
  # that's what we do by default if no cntr is around.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify
}

#
# Testcase #4.
#
@test "[userns] pre-existing & unprocessed dockerd config (non-sysbox runtime) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

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

  install_sysbox 0

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode. Also, we
  # would restart anyways to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'userns' to 'shiftfs' mode, as
  # that's what we do by default if no cntr is around.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  # Verify that the non-sysbox (dummy) runtime is left untouched in docker config.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq --exit-status '.runtimes | has(\"dummy-runc\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]

  uninstall_verify
}

#
# Testcase #5.
#
@test "[userns] pre-existing & processed dockerd config (non-sysbox runtime) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

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

  install_sysbox 0

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode. Also, we
  # would restart anyways to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'userns' to 'shiftfs' mode, as
  # that's what we do by default if no cntr is around.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  # Verify that the non-sysbox (dummy) runtime is left untouched in docker config.
  run sh -c "jq --exit-status 'has(\"runtimes\")' ${dockerCfgFile} &&
             jq --exit-status '.runtimes | has(\"dummy-runc\")' ${dockerCfgFile}"
  [ "$status" -eq 0 ]

  uninstall_verify
}

#
# Testcase #6.
#
# In 'shiftfs' nodes, verify that procesing a docker config with a userns entry,
# that has *not* been digested by dockerd, will not force the installer to change
# to 'userns-remap' mode. IOW, dockerd will continue operating in the same mode
# and discard this transient configuration. The transition to 'userns' mode will
# need to be manually made by docker_config_userns_mode() instruction.
#
@test "[userns] pre-existing & unprocessed dockerd config (sysbox userns) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode. Also, we
  # would restart anyways to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'userns' to 'shiftfs' mode, as
  # that's what we do by default if no cntr is around.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify
}

#
# Testcase #7.
#
@test "[userns] pre-existing & processed dockerd config (sysbox userns) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Docker is already operating in 'userns' mode, so in principle there's no need to restart
  # docker here. However, docker network's config is missing so a restart is needed.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'userns' to 'shiftfs' mode, as
  # that's what we do by default if no cntr is around.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify
}

#
# Testcase #8.
#
@test "[userns] pre-existing & unprocessed dockerd config (non-sysbox userns) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "non-sysbox"
}
EOF

  run useradd non-sysbox
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  # Restart docker to force transient config changes to be processed.
  run systemctl restart docker
  [ "$status" -eq 0 ]

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode (not in 'userns'
  # mode yet). Also, we would restart anyways to process network configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that the original 'userns-remap' entry, and no other, is still present
  # in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"non-sysbox\""
  [ "$status" -eq 0 ]
    run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q '\"sysbox\"'"
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did *not* restart as there's no sysbox userns entry to delete.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Docker should continue operating in 'userns' mode.
  verify_userns_mode

  uninstall_verify

  run userdel non-sysbox
  [ "$status" -eq 0 ]
}

#
# Testcase #9.
#
@test "[userns] pre-existing & processed dockerd config (non-sysbox userns) -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "non-sysbox"
}
EOF

  run useradd non-sysbox
  [ "$status" -eq 0 ]

  # Cold-boot dockerd to process above config.
  run systemctl restart docker
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Docker is already operating in 'userns' mode, so in principle there's no need to restart
  # docker here. However, docker network's config is missing so a restart is needed.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that the original 'userns-remap' entry, and no other, is still present
  # in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"non-sysbox\""
  [ "$status" -eq 0 ]
    run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q '\"sysbox\"'"
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did *not* restart as there's no sysbox userns entry to delete.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Docker should continue operating in 'userns' mode.
  verify_userns_mode

  uninstall_verify

  run userdel non-sysbox
  [ "$status" -eq 0 ]
}

#
# Testcase #10.
#
@test "[userns] no pre-existing dockerd config & existing cntrs -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

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

  docker_config_userns_mode

  install_verify

  # Check dockerd did restart to switch to 'userns' mode and to process network
  # configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  # Dockerd has been restarted so it should have be operating in 'userns' mode now.
  verify_userns_mode

  uninstall_sysbox purge

  # Check dockerd did restart during uninstallation.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid1}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

#
# Testcase #11.
#
@test "[userns] pre-existing & unprocessed dockerd config (sysbox userns) & existing cntrs -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

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

  docker_config_userns_mode

  install_verify

  # Check dockerd did restart to switch to 'userns' mode and to process network
  # configuration change.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # We are now in 'userns' mode.
  verify_userns_mode

  # Initialize a new regular container, which should have any impact on the
  # uninstallation process further below as we're in 'auto' mode (can't complete).
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check uninstallation output. A docker-restart warning *is* expected as we are
  # operating in 'autol' userns config mode and there's a container.
  run sh -c 'echo "${uninstallation_output}" | egrep -q "Docker service was not restarted"'
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 0 ]

  # Check dockerd did not restart during uninstallation.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Still operating in 'userns' mode due to docker not restarted.
  verify_userns_mode

  uninstall_verify

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

#
# Testcase #12.
#
@test "[userns] pre-existing & processed dockerd config (sysbox userns) & existing cntrs -- automatic config" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_userns_remap true

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

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No docker-restart warning expected as docker is
  # already operating in 'userns' mode.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd is already operating in 'userns' mode, but it must be restarted for the
  # new network configuration to be processed.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check dockerd did restart during uninstallation.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

#
# Testcase #13.
#
@test "[userns] no pre-existing dockerd config -- manual config" {

  docker_return_defaults

  config_automatic_userns_remap false

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must be restarted to process the new network configuration changes, but
  # userns-remap changes are left for the user to introduce.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -ne 0 ]

  # Notice that runtime is added in manual-config mode.
  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # Dockerd should still be operating in 'shiftfs' mode.
  verify_shiftfs_mode

  # Let's now manually push the required config and restart dockerd.
  jq --indent 4 '. + {"userns-remap": "sysbox"}' \
    ${dockerCfgFile} > tmp.json && mv tmp.json ${dockerCfgFile}

  run systemctl restart docker
  [ "$status" -eq 0 ]

  # Dockerd should be in 'userns-mode' mode now.
  verify_userns_mode

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode. Also docker's network-config is left
  # untouched, so no need to restart.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  # Notice that runtime is always deleted, even in 'manual' mode, as this doesn't
  # involve a cold restart.
  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Verify that the 'userns-remap' entry has not been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_userns_mode

  uninstall_verify
}

#
# Testcase #14.
#
@test "[userns] pre-existing & unprocessed dockerd config (sysbox runtime) -- manual config" {

  docker_return_defaults

  config_automatic_userns_remap false

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

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must restart to process the network config changes. No changes are expected
  # in regards to 'userns-remap' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -ne 0 ]

  # Notice that runtime is added in manual-config mode.
  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # Still in 'shiftfs' mode as 'userns-remap' config has not been changed.
  verify_shiftfs_mode

  # Let's now manually push the 'userns-remap' required config and restart dockerd.
  jq --indent 4 '. + {"userns-remap": "sysbox"}' \
    ${dockerCfgFile} > tmp.json && mv tmp.json ${dockerCfgFile}

  run systemctl restart docker
  [ "$status" -eq 0 ]

  # Dockerd should be in 'userns-mode' mode now.
  verify_userns_mode

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check uninstallation output in 'manual restart' mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode. Also docker's network-config is left
  # untouched, so no need to restart.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Verify that the 'userns-remap' entry has not been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

#
# Testcase #15.
#
@test "[userns] pre-existing & processed dockerd config (sysbox runtime) -- manual config" {

  docker_return_defaults

  config_automatic_userns_remap false

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

  install_sysbox 0

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must restart to process the network config changes. No changes are expected
  # in regards to 'userns-remap' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that no 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -ne 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # Still in 'shiftfs' mode as 'userns-remap' config has not been changed.
  verify_shiftfs_mode

  # Let's now manually push the 'userns-remap' required config and restart dockerd.
  jq --indent 4 '. + {"userns-remap": "sysbox"}' \
    ${dockerCfgFile} > tmp.json && mv tmp.json ${dockerCfgFile}

  run systemctl restart docker
  [ "$status" -eq 0 ]

  # Dockerd should be in 'userns-mode' mode now.
  verify_userns_mode

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check installation output in 'manual restart' mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode. Also docker's network-config is left
  # untouched, so no need to restart.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Verify that the 'userns-remap' entry has not been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

#
# Testcase #16.
#
@test "[userns] pre-existing & unprocessed dockerd config (sysbox userns) -- manual config" {

  docker_return_defaults

  config_automatic_userns_remap false

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox 0

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must restart to process the network config changes. Also, due to 'userns-remap'
  # config already present, but unprocessed, docker should be operating in this mode
  # after the restart.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # Verify docker is operating in 'userns' mode.
  verify_userns_mode

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check installation output in 'manual restart' mode.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode. Also docker's network-config is left
  # untouched, so no need to restart.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Verify that the 'userns-remap' entry has not been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

#
# Testcase #17.
#
@test "[userns] pre-existing & processed dockerd config (sysbox userns) -- manual config" {

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must restart to process the network config changes. No changes are expected
  # in 'userns-remap' config front.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check uninstallation output. No dockerd restart warning expected.
  run sh -c "echo \"${uninstallation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode. Also docker's network-config is left
  # untouched, so no need to restart.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Verify that the 'userns-remap' entry has not been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

#
# Testcase #18.
#
@test "[userns] pre-existing & unprocessed dockerd config (sysbox userns) & existing cntrs -- manual config" {

  docker_return_defaults

  config_automatic_userns_remap false

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

  docker_config_userns_mode

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around anymore.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  echo "installation_output = ${installation_output}"
  [ "$status" -ne 0 ]

  # Dockerd must restart to process the network config changes. No changes are expected
  # in 'userns-remap' config front.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # We are in 'userns' mode.
  verify_userns_mode

  # Initialize a new regular container. Shouldn't have any impact on the uninstallation
  # process further below as we're in 'manual' mode.
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check installation output. A docker-restart warning is *not* expected as we are
  # operating in 'manual' restart mode.
  run sh -c 'echo "${uninstallation_output}" | egrep -q "Docker service was not restarted"'
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -ne 0 ]

  # No docker restart in 'manual' mode. Also docker's network-config is left
  # untouched, so no need to restart.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_userns_mode

  uninstall_verify

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

#
# Testcase #19.
#
@test "[userns] pre-existing & processed dockerd config (sysbox userns) & existing cntrs -- manual config" {

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around anymore.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Dockerd must restart to process the network config changes. No changes are expected
  # in 'userns-remap' config front.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" != "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  # Initialize a new regular container. Shouldn't have any impact on the uninstallation
  # process further below as we're in 'manual' mode.
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check uninstallation output. A docker-restart warning is *not* expected as we are
  # operating in 'manual' restart mode.
  run sh -c 'echo "${uninstallation_output}" | egrep -q "Docker service was not restarted"'
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -ne 0 ]

  # No docker restart in 'manual' mode. Also docker's network-config is left
  # untouched, so no need to restart.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_userns_mode

  uninstall_verify

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

#
# Testcase #20.
#
# Ensure that this testcase always execute as this one initializes the testing
# environment for this test-suite. See "Case 1)" in sysbox.config.
#
@test "[userns] pre-existing dockerd config with all required elems -- automatic config" {

  docker_return_defaults

  config_automatic_userns_remap true

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox",
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

  verify_userns_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

  uninstall_sysbox purge

  # Check dockerd did restart as we are in 'automatic' docker-config mode, and
  # as such, sysbox uninstaller eliminates 'userns' docker entry if no existing
  # containers are found.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" != "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}

#
# Testcase #21.
#
# Ensure that this testcase always execute as this one initializes the testing
# environment for this test-suite. See "Case 1)" in sysbox.config.
#
@test "[userns] pre-existing dockerd config with all required elems -- manual config" {

  docker_return_defaults

  config_automatic_userns_remap false

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox",
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

  verify_userns_mode

  verify_docker_bip_presence

  verify_docker_address_pool_presence

  uninstall_sysbox purge

  # Check dockerd did **not** restart as we are in 'manual' docker-config mode, and
  # as such, sysbox uninstaller leaves 'userns' config untouched.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_userns_mode

  uninstall_verify

  # Both 'bip' and 'address-pool' attributes are left untouched in docker config.
  verify_docker_bip_presence

  verify_docker_address_pool_presence
}