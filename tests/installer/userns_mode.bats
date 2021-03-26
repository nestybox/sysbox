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

# Ensure that this testcase always execute as this one initializes the testing
# environment for this test-suite.
@test "no pre-existing dockerd config -- automatic restart" {

  install_init

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode, as
  # that's what we do by default if no cntr is around.
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

@test "pre-existing & unprocessed dockerd config (sysbox runtime) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode, as
  # that's what we do by default if no cntr is around.
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

@test "pre-existing & processed dockerd config (sysbox runtime) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode, as
  # that's what we do by default if no cntr is around.
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

@test "pre-existing & unprocessed dockerd config (non-sysbox runtime) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode, as
  # that's what we do by default if no cntr is around.
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

@test "pre-existing & processed dockerd config (non-sysbox runtime) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode, as
  # that's what we do by default if no cntr is around.
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

# In 'shiftfs' nodes, verify that procesing a docker config with a userns entry,
# that has *not* been digested by dockerd, will not force the installer to change
# to 'userns-remap' mode. IOW, dockerd will continue operating in the same mode.
@test "pre-existing & unprocessed dockerd config (sysbox userns) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart when switching from 'shiftfs' to 'userns' mode, as
  # that's what we do by default if no cntr is around.
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

@test "pre-existing & processed dockerd config (sysbox userns) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

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

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did *not* restart as docker is already operating on 'userns' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

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

@test "pre-existing & unprocessed dockerd config (non-sysbox userns) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "non-sysbox"
}
EOF

  run useradd non-sysbox
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did restart as docker is not operating in 'userns' mode yet.
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

@test "pre-existing & processed dockerd config (non-sysbox userns) -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

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

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did *not* restart as docker is already operating on 'userns' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

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

@test "no pre-existing dockerd config & existing cntrs -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

  # Initialize a regular container.
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. Installer is expected to generate a warning and avoid
  # restarting docker due to the presence of a container.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  [ "$status" -eq 0 ]

  # Check dockerd did not restart as explained above.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  # Dockerd has not been restarted so it should have continued operating in 'shiftfs'
  # mode.
  verify_shiftfs_mode

  uninstall_sysbox purge

  # Check installation output. (Un)installer is expected to generate a warning and
  # avoid restarting docker due to the presence of a container.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  [ "$status" -eq 0 ]

  # Check dockerd did not restart across the entire install / uninstall cycle.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid1}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

@test "pre-existing & unprocessed dockerd config (sysbox userns) & existing cntrs -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  # Initialize a regular container.
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. A docker-restart warning is expected as docker is
  # attempting to switch from 'shiftfs' to 'userns' mode, but there is an existing
  # container.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 0 ]

  # Check dockerd did not restart due to existing container.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # We are still in 'shiftfs' mode.
  verify_shiftfs_mode

  uninstall_sysbox purge

  # Check installation output. (Un)installer is expected to generate a warning and
  # avoid restarting docker due to the presence of a container.
  run sh -c 'echo "${uninstallation_output}" | egrep -q "Docker service was not restarted"'
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 0 ]

  # Check dockerd did not restart due to existing container.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_shiftfs_mode

  uninstall_verify

  # Remove container.
  run docker rm alpine
  [ "$status" -eq 0 ]
}

@test "pre-existing & processed dockerd config (sysbox userns) & existing cntrs -- automatic restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart true

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

  install_sysbox

  install_verify

  # Check installation output. No docker-restart warning expected as docker is
  # already operating in 'userns' mode.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did not restart as docker is already operating in 'userns' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check installation output. (Un)installer is expected to generate a warning and
  # avoid restarting docker due to the presence of a container.
  run sh -c 'echo "${uninstallation_output}" | egrep -q "Docker service was not restarted"'
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -eq 0 ]

  # Check dockerd did not restart due to existing container.
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

@test "no pre-existing dockerd config -- manual docker restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart false

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected as there are no
  # cntrs around.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did not restart as we are dealing with the 'manual' scenario.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  # Notice that runtime is always added, even in 'manual' mode, as this doesn't
  # involve a cold restart.
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

  # Check dockerd did *not* restart when switching from 'userns' to 'shiftfs' mode,
  # as we are operating in 'manual' mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  # Verify that the 'userns-remap' entry has been eliminated from docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -ne 0 ]

  # Notice that runtime is always deleted, even in 'manual' mode, as this doesn't
  # involve a cold restart.
  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  verify_userns_mode

  uninstall_verify
}

@test "pre-existing & unprocessed dockerd config (sysbox runtime) -- manual restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart false

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

  # Check installation output. No dockerd restart warning expected as we don't
  # even attempt to do that in 'manual restart' mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # Still in 'shiftfs' mode as docker has not been restarted.
  verify_shiftfs_mode

  # Let's manually restart docker now.
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

  # No docker restart in 'manual' mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

@test "pre-existing & processed dockerd config (sysbox runtime) -- manual restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart false

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

  # Check installation output. No dockerd restart warning expected as we don't
  # even attempt to do that in 'manual restart' mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry has been added to docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # Still in 'shiftfs' mode as docker has not been restarted.
  verify_shiftfs_mode

  # Let's manually restart docker now.
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

  # No docker restart in 'manual' mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

@test "pre-existing & unprocessed dockerd config (sysbox userns) -- manual restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart false

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. No dockerd restart warning expected as we don't
  # even attempt to do that in 'manual restart' mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # Still in 'shiftfs' mode as docker has not been restarted.
  verify_shiftfs_mode

  # Let's manually restart docker now.
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

  # No docker restart in 'manual' mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

@test "pre-existing & processed dockerd config (sysbox userns) -- manual restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart false

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

  # Check installation output. No dockerd restart as we are already in 'userns'
  # mode.
  run sh -c "echo \"${installation_output}\" | egrep -q \"Docker service was not restarted\""
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # No docker restart in 'manual' mode. Also, docker is already in 'userns' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

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

  # No docker restart in 'manual' mode.
  local dockerPid3=$(pidof dockerd)
  [ "${dockerPid3}" == "${dockerPid2}" ]

  verify_docker_config_sysbox_runtime_absence

  verify_docker_sysbox_runtime_absence

  # Still in 'userns' mode.
  verify_userns_mode

  uninstall_verify
}

@test "pre-existing & unprocessed dockerd config (sysbox userns) & existing cntrs -- manual restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart false

  sudo cat > /etc/docker/daemon.json <<EOF
{
    "userns-remap": "sysbox"
}
EOF

  # Initialize a regular container.
  run docker run -d --name alpine alpine
  [ "$status" -eq 0 ]

  local dockerPid1=$(pidof dockerd)

  install_sysbox

  install_verify

  # Check installation output. A docker-restart warning is *not* expected as we are
  # operating in 'manual' restart mode.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  echo "installation_output = ${installation_output}"
  [ "$status" -ne 0 ]

  # Check dockerd did not restart due to 'manual' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  # We are still in 'shiftfs' mode.
  verify_shiftfs_mode

  # Let's manually restart docker now.
  run systemctl restart docker
  [ "$status" -eq 0 ]

  # Dockerd should be in 'userns-mode' mode now.
  verify_userns_mode

  # Obtain the new dockerd pid.
  local dockerPid2=$(pidof dockerd)

  uninstall_sysbox purge

  # Check installation output. A docker-restart warning is *not* expected as we are
  # operating in 'manual' restart mode.
  run sh -c 'echo "${uninstallation_output}" | egrep -q "Docker service was not restarted"'
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -ne 0 ]

  # Check dockerd did not restart due to existing container.
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

@test "pre-existing & processed dockerd config (sysbox userns) & existing cntrs -- manual restart" {

  docker_return_defaults

  disable_shiftfs

  config_automatic_restart false

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

  install_sysbox

  install_verify

  # Check installation output. No docker-restart warning expected as docker is
  # already operating in 'userns' mode.
  run sh -c 'echo "${installation_output}" | egrep -q "Docker service was not restarted"'
  echo "installation_output = ${installation_output}"
  [ "$status" -eq 1 ]

  # Check dockerd did not restart as docker is already operating in 'userns' mode.
  local dockerPid2=$(pidof dockerd)
  [ "${dockerPid2}" == "${dockerPid1}" ]

  # Verify that a 'userns-remap' entry is present in docker config.
  run sh -c "jq --exit-status 'has(\"userns-remap\")' ${dockerCfgFile} &&
             jq --exit-status '.\"userns-remap\"' ${dockerCfgFile} | egrep -q \"sysbox\""
  [ "$status" -eq 0 ]

  verify_docker_config_sysbox_runtime_presence

  verify_docker_sysbox_runtime_presence

  verify_userns_mode

  uninstall_sysbox purge

  # Check installation output. A docker-restart warning is *not* expected as we are
  # operating in 'manual' restart mode.
  run sh -c 'echo "${uninstallation_output}" | egrep -q "Docker service was not restarted"'
  echo "uninstallation_output = ${uninstallation_output}"
  [ "$status" -ne 0 ]

  # Check dockerd did not restart due to existing container.
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