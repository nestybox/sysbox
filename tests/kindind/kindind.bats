#!/usr/bin/env bats

# Tests for deploying a k8s-in-docker-in-docker (i.e., an entire k8s-in-docker
# cluster inside a sysbox container).

load ../helpers/run
load ../helpers/docker
load ../helpers/systemd
load ../helpers/sysbox-health

function kind_node_ready() {
   local syscont=$1
   local node=$2

   __docker exec $syscont sh -c "kubectl get node $node"
   [ "$status" -eq 0 ]

   res=$(echo ${lines[1]} | awk '{print $2}' | grep -qw Ready)
   if [ $? -eq 0 ]; then
		return 0
   else
      return 1
	fi
}

function kind_deployment_ready() {
   local syscont=$1
   local depl=$2

   __docker exec $syscont sh -c "kubectl get deployment $depl"
	[ "$status" -eq 0 ]

	res=$(echo ${lines[1]} | awk '{print $2}')
	if [[ "$res" == "1/1" ]]; then
		return 0
	else
		return 1
	fi
}

function teardown() {
  sysbox_log_check
}

@test "kindind basic v1.18" {

   local sc=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

	# Install KinD inside the system container
	docker exec "$sc" sh -c \
			 "cd /root && \
			  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64 && \
			  chmod +x kind
			  cp kind /usr/bin/kind"

	# Install kubectl inside the system container
	docker exec "$sc" sh -c \
			 "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && \
			 install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"

	# Start dockerd inside the system container
	docker exec -d "$sc" sh -c "dockerd > /var/log/dockerd.log 2>&1"
	[ "$status" -eq 0 ]

	wait_for_inner_dockerd $sc

	# Create the KinD cluster inside the system container
	#
	# NOTE: the official kindest/node:v1.18.19 image requires cgroups v2 be
	# enabled on the host. The nestybox/kindestnode:v1.18.19 image relaxes this
	# requirement (since it does not apply for Sysbox containers). This check
	# will be relaxed in the very near future in the KinD image itself (see this
	# PR: https://github.com/kubernetes-sigs/kind/pull/2498).

   docker exec "$sc" sh -c "kind create cluster --image=${CTR_IMG_REPO}/kindestnode:v1.18.19"
   [ "$status" -eq 0 ]

   docker exec "$sc" sh -c "kubectl cluster-info --context kind-kind"
   [ "$status" -eq 0 ]

   # wait for cluster to be ready ...
   retry_run 30 2 "kind_node_ready $sc kind-control-plane"

   # deploy pod and verify it's up
   docker exec "$sc" sh -c "kubectl create deployment nginx --image=nginx"
   [ "$status" -eq 0 ]

   retry_run 60 2 "kind_deployment_ready $sc nginx"

   docker_stop "$sc"
}

@test "kindind basic v1.19" {

   local sc=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

	# Install KinD inside the system container
	docker exec "$sc" sh -c \
			 "cd /root && \
			  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64 && \
			  chmod +x kind
			  cp kind /usr/bin/kind"

	# Install kubectl inside the system container
	docker exec "$sc" sh -c \
			 "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && \
			 install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"

	# Start dockerd inside the system container
	docker exec -d "$sc" sh -c "dockerd > /var/log/dockerd.log 2>&1"
	[ "$status" -eq 0 ]

	wait_for_inner_dockerd $sc

	# Create the KinD cluster inside the system container
	#
	# NOTE: the official kindest/node:v1.19.11 image requires cgroups v2 be
	# enabled on the host. The nestybox/kindestnode:v1.19.11 image relaxes this
	# requirement (since it does not apply for Sysbox containers). This check
	# will be relaxed in the very near future in the KinD image itself (see this
	# PR: https://github.com/kubernetes-sigs/kind/pull/2498).

   docker exec "$sc" sh -c "kind create cluster --image=${CTR_IMG_REPO}/kindestnode:v1.19.11"
   [ "$status" -eq 0 ]

   docker exec "$sc" sh -c "kubectl cluster-info --context kind-kind"
   [ "$status" -eq 0 ]

   # wait for cluster to be ready ...
   retry_run 30 2 "kind_node_ready $sc kind-control-plane"

   # deploy pod and verify it's up
   docker exec "$sc" sh -c "kubectl create deployment nginx --image=nginx"
   [ "$status" -eq 0 ]

   retry_run 60 2 "kind_deployment_ready $sc nginx"

   docker_stop "$sc"
}

@test "kindind basic v1.20" {

   local sc=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

	# Install KinD inside the system container
	docker exec "$sc" sh -c \
			 "cd /root && \
			  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64 && \
			  chmod +x kind
			  cp kind /usr/bin/kind"

	# Install kubectl inside the system container
	docker exec "$sc" sh -c \
			 "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && \
			 install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"

	# Start dockerd inside the system container
	docker exec -d "$sc" sh -c "dockerd > /var/log/dockerd.log 2>&1"
	[ "$status" -eq 0 ]

	wait_for_inner_dockerd $sc

	# Create the KinD cluster inside the system container
	#
	# NOTE: the official kindest/node:v1.20.7 image requires cgroups v2 be
	# enabled on the host. The nestybox/kindestnode:v1.20.7 image relaxes this
	# requirement (since it does not apply for Sysbox containers). This check
	# will be relaxed in the very near future in the KinD image itself (see this
	# PR: https://github.com/kubernetes-sigs/kind/pull/2498).

   docker exec "$sc" sh -c "kind create cluster --image=${CTR_IMG_REPO}/kindestnode:v1.20.7"
   [ "$status" -eq 0 ]

   docker exec "$sc" sh -c "kubectl cluster-info --context kind-kind"
   [ "$status" -eq 0 ]

   # wait for cluster to be ready ...
   retry_run 30 2 "kind_node_ready $sc kind-control-plane"

   # deploy pod
   docker exec "$sc" sh -c "kubectl create deployment nginx --image=nginx"
   [ "$status" -eq 0 ]

   retry_run 60 2 "kind_deployment_ready $sc nginx"

   docker_stop "$sc"
}
