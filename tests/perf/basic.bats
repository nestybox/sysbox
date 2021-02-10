#!/usr/bin/env bats

#
# Basic performance tests for Sysbox
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "syscont-inner-img-preload parallel start" {

   # Verify that we can launch a number of sys-containers in parallel and we
   # don't hit timeouts (in Docker or Sysbox). In this test we choose a sys
   # container image that comes preloaded with inner containers (e.g.,
   # ${CTR_IMG_REPO}/k8s-node). This causes strain on Sysbox because when each
   # container starts it needs to copy those inner images from the container's
   # root file system (on overlayfs) into a sysbox data store. These copy
   # operations can take a while especially when the number of containers
   # exceeds the number of CPUs in the machine.

   local num_cpus=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
   local num_syscont=$((num_cpus*2))

   [ "$num_syscont" -ge 1 ]

	# pull image before launching containers (to avoid multiple pulls in parallel)
	docker pull ${CTR_IMG_REPO}/k8s-node:v1.18.2

   seq 0 $(($num_syscont-1)) | xargs -P${num_syscont} -I {} docker run --runtime=sysbox-runc -d --rm --name syscont{} --hostname syscont{} ${CTR_IMG_REPO}/k8s-node:v1.18.2

   # verify all containers are up
   for i in $(seq 0 $((num_syscont-1))); do
      docker exec syscont$i hostname
      [ "$status" -eq 0 ]
      [ "$output" = "syscont$i" ]
   done

   seq 0 $(($num_syscont-1)) | xargs -P${num_syscont} -I {} docker stop -t0 syscont{}
}
