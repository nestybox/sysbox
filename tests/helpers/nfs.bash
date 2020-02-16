#!/bin/bash -x

#
# nfs test helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

# Starts an nfs server in a privileged container, exposing a host volume.
function nfs_server_container_start {
  local nfs_share=$1
  local export_file=$2

  modprobe {nfs,nfsd}
  nfs_srv=$(docker run --rm -d --runtime=runc -v $nfs_share:$nfs_share -v $export_file:/etc/exports:ro --cap-add SYS_ADMIN -p 2049:2049 erichough/nfs-server)
  echo $nfs_srv
}

function nfs_server_container_stop() {
  local nfs_srv=$1
  docker_stop $nfs_srv
}
