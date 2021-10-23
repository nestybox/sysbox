#!/usr/bin/env bats

# Tests for deploying a k8s-in-docker-in-docker (i.e., an entire k8s-in-docker
# cluster inside a sysbox container).

load ../helpers/run
load ../helpers/docker
load ../helpers/systemd
load ../helpers/sysbox-health

SYSCONT_IMAGE=nestybox/kindind

function kind_node_ready() {
   local syscont=$1
   local node=$2

   docker exec $syscont sh -c "docker exec $sc sh -c \"kubectl get node $node\""
   if [ "$status" -eq 0 ]; then
      res=$(echo ${lines[1]} | awk '{print $2}' | grep -qw Ready)
      echo $?
   else
      echo 1
  fi
}

function kind_deployment_ready() {
   local syscont=$1
   local depl=$2

   docker exec $syscont sh -c "docker exec $sc sh -c \"kubectl get deployment $depl\""
   if [ "$status" -eq 0 ]; then
      res=$(echo ${lines[1]} | awk '{print $2}' | grep -qw "1/1")
      echo $?
   else
      echo 1
  fi
}

function teardown() {
  sysbox_log_check
}

@test "kindind basic v1.18" {

   local sc=$(docker_run --rm $SYSCONT_IMAGE)

   wait_for_inner_systemd $sc

	# The official kindest/node:v1.18.19 image requires cgroups v2 be enabled on
	# the host. The nestybox/kindestnode:v1.18.19 image relaxes this requirement
	# (does no apply for Sysbox containers). This check will be relaxed in the
	# very near future (see this PR:
	# https://github.com/kubernetes-sigs/kind/pull/2498).

   docker exec "$sc" sh -c "kind create cluster --image=${CTR_IMG_REPO}/kindestnode:v1.18.19"
   [ "$status" -eq 0 ]

   docker exec "$sc" sh -c "kubectl cluster-info --context kind-kind"
   [ "$status" -eq 0 ]

   # wait for cluster to be ready ...
   retry_run 30 2 "kind_node_ready $sc kind-control-plane"

   # deploy pod
   docker exec "$sc" sh -c "kubectl create deployment nginx --image=nginx"
   [ "$status" -eq 0 ]

   retry_run 15 2 "kind_deployment_ready $sc kind-control-plane"

   docker_stop "$sc"
}

@test "kindind basic v1.19" {

   local sc=$(docker_run --rm $SYSCONT_IMAGE)

   wait_for_inner_systemd $sc

	# The official kindest/node:v1.19.11 image requires cgroups v2 be enabled on
	# the host. The nestybox/kindestnode:v1.19.11 image relaxes this requirement
	# (does no apply for Sysbox containers). This check will be relaxed in the
	# very near future (see this PR:
	# https://github.com/kubernetes-sigs/kind/pull/2498).

   docker exec "$sc" sh -c "kind create cluster --image=${CTR_IMG_REPO}/kindestnode:v1.19.11"
   [ "$status" -eq 0 ]

   docker exec "$sc" sh -c "kubectl cluster-info --context kind-kind"
   [ "$status" -eq 0 ]

   # wait for cluster to be ready ...
   retry_run 30 2 "kind_node_ready $sc kind-control-plane"

   # deploy pod
   docker exec "$sc" sh -c "kubectl create deployment nginx --image=nginx"
   [ "$status" -eq 0 ]

   retry_run 15 2 "kind_deployment_ready $sc kind-control-plane"

   docker_stop "$sc"
}

@test "kindind basic v1.20" {

   local sc=$(docker_run --rm $SYSCONT_IMAGE)

   wait_for_inner_systemd $sc

	# The official kindest/node:v1.20.7 image requires cgroups v2 be enabled on
	# the host. The nestybox/kindestnode:v1.20.7 image relaxes this requirement
	# (does no apply for Sysbox containers). This check will be relaxed in the
	# very near future (see this PR:
	# https://github.com/kubernetes-sigs/kind/pull/2498).

   docker exec "$sc" sh -c "kind create cluster --image=${CTR_IMG_REPO}/kindestnode:v1.20.7"
   [ "$status" -eq 0 ]

   docker exec "$sc" sh -c "kubectl cluster-info --context kind-kind"
   [ "$status" -eq 0 ]

   # wait for cluster to be ready ...
   retry_run 30 2 "kind_node_ready $sc kind-control-plane"

   # deploy pod
   docker exec "$sc" sh -c "kubectl create deployment nginx --image=nginx"
   [ "$status" -eq 0 ]

   retry_run 15 2 "kind_deployment_ready $sc kind-control-plane"

   docker_stop "$sc"
   docker image rm $SYSCONT_IMAGE
}
