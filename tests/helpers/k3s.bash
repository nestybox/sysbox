#!/bin/bash

load ../helpers/run
load ../helpers/docker
load ../helpers/systemd
load ../helpers/fs
load ../helpers/k8s

# Wait for all worker nodes to be connected to master.
function k3s_all_nodes_ready() {
  local cluster=$1
  local num_workers=$2
  local delay=$3

  local timestamp=$(date +%s)
  local timeout=$(($timestamp + $delay))
  local all_ok

  while [ $timestamp -lt $timeout ]; do
    all_ok="true"

    for ((i = 1; i <= $num_workers; i++)); do
      master=${cluster}-master
      worker=${cluster}-worker-${i}

      run k8s_node_ready $worker
      if [ "$status" -ne 0 ]; then
        all_ok="false"
        break
      fi
    done

    if [[ "$all_ok" == "true" ]]; then
      break
    fi

    sleep 2
    timestamp=$(date +%s)
  done

  if [[ "$all_ok" != "true" ]]; then
    echo 1
  else
    echo 0
  fi
}

# Deploys a k3s cluster through k3sup tool. The cluster has one master node
# and the given number of worker nodes. The cluster uses the K8s flannel cni.
#
# usage: k3s_cluster_setup <cluster_name> <num_workers> <network> <node_image> <k8s_version>
#
# cluster: name of the cluster; nodes in the cluster are named "<cluster_name>-master",
#          "<cluster-name>-worker-1", "<cluster-name>-worker-2", etc.
# num_workers: number of k3s worker nodes
# network: docker network to which the k3s nodes are connected (e.g., bridge,
#          user-defined, etc.)
#
function k3s_cluster_setup() {
  local cluster=$1
  local num_workers=$2
  local net=$3
  local node_image=$4
  local k8s_version=$5
  local cni=$6

  local pod_net_cidr=10.244.0.0/16
  local master_node=${cluster}-master

  # Install k3sup.
  curl -sLS https://get.k3sup.dev | sh
  [ "$status" -eq 0 ]

  # Create master and worker nodes.
  docker_run --rm --name=${master_node} --hostname=${master_node} ${node_image}
  [ "$status" -eq 0 ]

  for i in $(seq 1 ${num_workers}); do
    local node=${cluster}-worker-${i}

    docker_run --rm --name=${node} --hostname=${node} ${node_image}
    [ "$status" -eq 0 ]
  done

  wait_for_inner_systemd ${master_node}

  # Obtain master container ip-address.
  docker inspect -f "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${master_node}
  [ "$status" -eq 0 ]
  local master_node_ip=$output

  # Prepare ssh access.
  docker cp /root/.ssh/id_rsa.pub ${master_node}:/host_id_rsa.pub
  [ "$status" -eq 0 ]
  docker exec ${master_node} sh -c \
    "cat /host_id_rsa.pub >> /home/admin/.ssh/authorized_keys; chown admin:admin /home/admin/.ssh/authorized_keys; chmod 600 /home/admin/.ssh/authorized_keys"
  [ "$status" -eq 0 ]

  # Allow passwordless sudo access (k3sup requirement).
  docker exec ${master_node} bash -c \
    "echo 'admin ALL=(ALL) NOPASSWD: ALL' | sudo EDITOR='tee -a' visudo"
  [ "$status" -eq 0 ]

  # Install k3s.
  k3sup install --ip ${master_node_ip} --user admin
  [ "$status" -eq 0 ]

  # Repeat above instructions for each worker node.
  for i in $(seq 1 ${num_workers}); do
    local node=${cluster}-worker-${i}

    wait_for_inner_systemd ${node}

    # Obtain worker container ip-address.
    docker inspect -f "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${node}
    [ "$status" -eq 0 ]
    local node_ip=${output}

    # Prepare ssh access
    docker cp /root/.ssh/id_rsa.pub ${node}:/host_id_rsa.pub
    [ "$status" -eq 0 ]
    docker exec ${node} sh -c \
      "cat /host_id_rsa.pub >> /home/admin/.ssh/authorized_keys; chown admin:admin /home/admin/.ssh/authorized_keys; chmod 600 /home/admin/.ssh/authorized_keys"
    [ "$status" -eq 0 ]

    # Allow passwordless sudo access
    docker exec ${node} bash -c \
      "echo 'admin ALL=(ALL) NOPASSWD: ALL' | sudo EDITOR='tee -a' visudo"
    [ "$status" -eq 0 ]

    # Install k3s and join node to controller.
    k3sup join --ip ${node_ip} --server-ip ${master_node_ip} --user admin
    [ "$status" -eq 0 ]
  done

  # Set KUBECONFIG path.
  export KUBECONFIG=/root/nestybox/sysbox/kubeconfig
  [ "$status" -eq 0 ]
  kubectl config set-context default
  [ "$status" -eq 0 ]

  local join_timeout=$(($num_workers * 30))

  k3s_all_nodes_ready $cluster $num_workers $join_timeout
}

# Tears-down a k3s cluster created with k3s_cluster_setup().
#
function k3s_cluster_teardown() {
  local cluster=$1
  local num_workers=$2

  for i in $(seq 1 ${num_workers}); do
    node=${cluster}-worker-${i}

    docker stop -t0 ${node} 2>&1
    [ "$status" -eq 0 ]
  done

  docker stop -t0 ${cluster}-master
  [ "$status" -eq 0 ]

  # Delete cluster config.
  rm -rf ${KUBECONFIG}
}
