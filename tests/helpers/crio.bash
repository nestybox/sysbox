#!/bin/bash

#
# crictl Test Helper Functions
#
# Note: for tests using bats.
#

. $(dirname ${BASH_SOURCE[0]})/run.bash

export POD_MANIFEST_DIR=/root/nestybox/sysbox/tests/pods/manifests

# Given a pod's ID, return the associated host pid (i.e., the pid of the pod's pause container)
function crictl_pod_get_pid() {
	crictl inspectp $1 | jq ".info.pid"
}

# Given a pod's container ID, return the associated host pid
function crictl_cont_get_pid() {
	crictl inspect $1 | jq ".info.pid"
}

# Given a pod's container ID, return the associated pod ID
function crictl_cont_get_pod() {
	crictl inspect $1 | jq ".info.sandboxID" | tr -d '"'
}

# Get the host's uid assigned to the container's root user (user-ns mapping)
function crictl_root_uid_map() {
  local cont=$1
  local uid=$(crictl exec "$cont" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
  echo $uid
}

# Get the host's gid assigned to the container's root user (user-ns mapping)
function crictl_root_gid_map() {
  local cont=$1
  local gid=$(crictl exec "$cont" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
  echo $gid
}

function crictl_wait_for_inner_dockerd {
  local syscont=$1
  retry 10 1 "crictl exec $syscont docker ps"
}

# crictl does not have "copy" command (e.g., similar to "docker cp"); here we
# implement a similar one (though it won't work when the copy lands in a
# directory that is bind-mounted from a host dir).
#
# crictl_cp <container:source> <destination>
# crictl_cp <source> <container:destination>
#
# NOTE: Use with caution as no error checking is done on the arguments.
function crictl_cp {
	local source
	local dest
	local container
	local rootfs
	local direction

	if [[ "$1" == *":"* ]]; then
		container=$(echo $1 | cut -d ":" -f1)
		source=$(echo $1 | cut -d ":" -f2)
		dest=$2
		direction="from"
	elif [[ "$2" == *":"* ]]; then
		source=$1
		container=$(echo $2 | cut -d ":" -f1)
		dest=$(echo $2 | cut -d ":" -f2)
		direction="to"
	else
		return 1
	fi

	rootfs=$(crictl inspect $container | jq '.info.runtimeSpec.root.path' | tr -d '"')

	if [[ "$direction" == "from" ]]; then
		cp -rf "${rootfs}/$source" "$dest"
	else
		cp -rf "$source" "${rootfs}/$dest"
	fi

	return 0
}

function crictl_kubectl_config() {
  local node=$1
  local cluster_name=$2

  crictl exec ${node} sh -c "mkdir -p /root/.kube && \
    cp -i /etc/kubernetes/admin.conf /root/.kube/config && \
    chown $(id -u):$(id -g) /root/.kube/config"

  # Copy k8s config to the host to allow kubectl interaction.
  if [ ! -d ${HOME}/.kube ]; then
    crictl_cp ${node}:/root/.kube/. ${HOME}/.kube
    mv ${HOME}/.kube/config ${HOME}/.kube/${cluster_name}-config
  else
    crictl_cp ${node}:/root/.kube/config ${HOME}/.kube/${cluster_name}-config
  fi

  # As of today, kubeadm does not support 'multicluster' scenarios, so it generates
  # identical/overlapping k8s configurations for every new cluster. Here we are
  # simply adjusting the generated kubeconfig file to uniquely identify each cluster,
  # thereby allowing us to support multi-cluster setups.
  sed -i -e "s/^  name: kubernetes$/  name: ${cluster_name}/" \
    -e "s/^    cluster: kubernetes$/    cluster: ${cluster_name}/" \
    -e "s/^    user: kubernetes-admin$/    user: kubernetes-admin-${cluster_name}/" \
    -e "s/^  name: kubernetes-admin@kubernetes/  name: kubernetes-admin@${cluster_name}/" \
    -e "s/^current-context: kubernetes-admin@kubernetes/current-context: kubernetes-admin@${cluster_name}/" \
    -e "s/^- name: kubernetes-admin/- name: kubernetes-admin-${cluster_name}/" \
    -e "/^- name: kubernetes-admin/a\  username: kubernetes-admin" ${HOME}/.kube/${cluster_name}-config
  if [[ $? -ne 0 ]]; then
    ERR="failed to edit kubeconfig file for cluster ${cluster_name}"
    return 1
  fi

  export KUBECONFIG=${KUBECONFIG}:${HOME}/.kube/${cluster_name}-config
  kubectl config use-context kubernetes-admin@${cluster_name}
}
