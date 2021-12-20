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

#
# Deploys a k3s cluster with one controller/master node and 'n' worker nodes. Each
# K3s node runs inside a Sysbox container.
#
function k3s_cluster_setup() {
  local cluster=$1
  local num_workers=$2
  local k3s_version=$3
  local cni=$4
  local cluster_cidr=$5
  local node_image=$6
  local master_node=${cluster}-master
  local pubKey=$(cat ~/.ssh/id_rsa.pub)

  # Create master node and prepare ssh connectivity.
  docker_run --rm --name=${master_node} --hostname=${master_node} ${node_image}
  [ "$status" -eq 0 ]
  docker exec ${master_node} bash -c "mkdir -p ~/.ssh && echo $pubKey > ~/.ssh/authorized_keys"
  [ "$status" -eq 0 ]

  # Create worker nodes and prepare ssh connectivity.
  for i in $(seq 1 ${num_workers}); do
    local node=${cluster}-worker-${i}

    docker_run --rm --name=${node} --hostname=${node} ${node_image}
    [ "$status" -eq 0 ]

    docker exec ${node} bash -c "mkdir -p ~/.ssh && echo $pubKey > ~/.ssh/authorized_keys"
    [ "$status" -eq 0 ]
  done

  wait_for_inner_systemd ${master_node}

  # Controller's k3s installation.
  if [[ "$cni" == "flannel" ]]; then
    docker exec ${master_node} bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$k3s_version INSTALL_K3S_EXEC=\"--disable-network-policy --cluster-cidr=$cluster_cidr --disable=traefik\" sh -"
    [ "$status" -eq 0 ]
  else
    docker exec ${master_node} bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$k3s_version INSTALL_K3S_EXEC=\"--flannel-backend=none --disable-network-policy --cluster-cidr=$cluster_cidr --disable=traefik\" sh -"
    [ "$status" -eq 0 ]
  fi

  sleep 10

  # Obtain controller's ip address.
  docker inspect -f "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}" ${master_node}
  [ "$status" -eq 0 ]
  local controller_ip=$output

  # Obtain controller's k8s token.
  docker exec ${master_node} cat /var/lib/rancher/k3s/server/node-token
  [ "$status" -eq 0 ]
  local k8s_token=$output

  # Initialize control-plane in worker nodes.
  for i in $(seq 1 ${num_workers}); do
    local node=${cluster}-worker-${i}

    docker exec ${node} bash -c "curl -sfL https://get.k3s.io | K3S_URL=https://${controller_ip}:6443 K3S_TOKEN=${k8s_token} sh -"
    [ "$status" -eq 0 ]
  done

  run rm -rf config.yaml
  [ "$status" -eq 0 ]

  # Set KUBECONFIG path.
  export KUBECONFIG=/root/nestybox/sysbox/kubeconfig
  [ "$status" -eq 0 ]
  kubectl config set-context default
  [ "$status" -eq 0 ]
  docker cp ${master_node}:/etc/rancher/k3s/k3s.yaml kubeconfig
  [ "$status" -eq 0 ]
  run sed -i "s/127.0.0.1/${controller_ip}/" kubeconfig
  [ "$status" -eq 0 ]

  # If requested, install Calico requirements.
  if [[ "$cni" == "calico" ]]; then
    docker exec ${master_node} bash -c "kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml"
    [ "$status" -eq 0 ]

    docker exec ${master_node} bash -c "kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml"
    [ "$status" -eq 0 ]
  fi

  # Wait for workers to register.
  local join_timeout=$(($num_workers * 30))
  k3s_all_nodes_ready $cluster $num_workers $join_timeout

  # Wait till all kube-system pods have been initialized.
  retry_run 60 5 "k8s_all_pods_ready kube-system"

  # Also wait for calico ones.
  if [[ "$cni" == "calico" ]]; then
    retry_run 30 5 "k8s_all_pods_ready calico-system"
  fi
}

#
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
