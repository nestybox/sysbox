#!/usr/bin/env bats

#
# Verify NFS mount trapping & emulation by sysbox-fs
#
# (NFS client only; Sysbox does not support NFS server functionality;
# see sysbox issue #559).
#

load ../helpers/run
load ../helpers/nfs
load ../helpers/docker

@test "nfs mount" {

  skip "SYSBOX ISSUE #562"

  # setup an nfs server in a privileged container
  #
  # NOTE: the directory exported by the nfs server *must not* be on
  # overlayfs (it's not supported).

  local nfs_share=/mnt/scratch/nfs-share
  mkdir -p $nfs_share
  echo data > $nfs_share/file.txt
  echo "$nfs_share    *(rw,sync,no_subtree_check)" >> /etc/exports

  local nfs_srv=$(nfs_server_container_start $nfs_share /etc/exports)
  local nfs_srv_ip=$(docker_cont_ip $nfs_srv)

  # create a sys container (acts as an nfs client)
  local sc=$(docker_run --rm nestybox/ubuntu-bionic-systemd:latest)

  # ubuntu nfs clients need nfs-common pkg
  # TODO: bake nfs-common into the sys container image
  docker exec $sc sh -c "apt-get install -y nfs-common"
  [ "$status" -eq 0 ]

  # mount nfs inside the sys container
  docker exec $sc sh -c "mkdir -p /mnt/nfs-share"
  [ "$status" -eq 0 ]

  docker exec $sc sh -c "mount $nfs_srv_ip:$nfs_share /mnt/nfs-share"
  [ "$status" -eq 0 ]

  # verify the nfs mount works
  docker exec $sc sh -c "cat /mnt/nfs-share"
  [ "$status" -eq 0 ]

  local nfs_share_client=$output
  local nfs_share_server=$(cat $nfs_share)

  [ "$nfs_share_client" -eq "$nfs_share_server" ]

  # cleanup
  docker_stop "$sc"
  nfs_server_container_stop $nfs_srv
  sed -id '/^$nfs_share' /etc/exports
  rm -rf $nfs_share
}
