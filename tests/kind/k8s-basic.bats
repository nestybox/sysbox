#!/usr/bin/env bats

#
# Basic tests running K8s inside a system container
#

load ../helpers/run

function wait_for_inner_dockerd {
  local syscont=$1
  run retry_run 10 1 eval "__docker exec $syscont docker ps"
}

function kube_config() {
  local syscont=$1
  docker exec "$syscont" sh -c "mkdir -p $HOME/.kube"
  [ "$status" -eq 0 ]
  docker exec "$syscont" sh -c "cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
  [ "$status" -eq 0 ]
  docker exec "$syscont" sh -c "chown $(id -u):$(id -g) $HOME/.kube/config"
  [ "$status" -eq 0 ]
}

function flannel_config() {
  local syscont=$1
  docker exec "$syscont" sh -c "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
  [ "$status" -eq 0 ]
}

function kube_nodes_ready() {
  local syscont=$1
  local i

  docker exec "$syscont" sh -c "kubectl get nodes"
  [ "$status" -eq 0 ]

  len=${#lines[@]}
  for (( i=0; i<$len; i++ )); do
    if [ $i -ne 0 ]; then
      run sh -c "echo \"${lines[$i]}\" | awk '{print $2}' | grep \"NotReady\""
      if [ $status -eq 0 ]; then
        return 1
      fi
    fi
  done

  true
}

@test "kind basic" {

  #
  # Deploy a K8s master node, initialize it with kubeadm
  #

  local pod_net_cidr=10.244.0.0/16
  local k8s_master=$(docker_run --rm nestybox/ubuntu-bionic-k8s:latest)

  wait_for_inner_dockerd $k8s_master

  docker exec "$k8s_master" sh -c "kubeadm init --pod-network-cidr=$pod_net_cidr"
  [ "$status" -eq 0 ]
  local kubeadm_output=$output

  run sh -c "echo \"$kubeadm_output\" | grep -q \"Your Kubernetes control\-plane has initialized successfully\""
  [ "$status" -eq 0 ]

  run sh -c "echo \"$kubeadm_output\" | grep -A1 \"kubeadm join\""
  [ "$status" -eq 0 ]
  local kubeadm_join=$output

  kube_config $k8s_master
  flannel_config $k8s_master

  run retry_run 10 3 eval "kube_nodes_ready $k8s_master"

  #
  # Deploy a K8s worker node and join it to the cluster
  #

  local k8s_worker=$(docker_run --rm nestybox/ubuntu-bionic-k8s:latest)

  wait_for_inner_dockerd $k8s_worker

  docker exec "$k8s_worker" sh -c "$kubeadm_join"
  [ "$status" -eq 0 ]

  #
  # Verify the k8s cluster is up
  #

  run retry_func 10 3 eval "kube_nodes_ready $k8s_master"

  # Cleanup
  docker_stop "$k8s_master"
  docker_stop "$k8s_worker"
}
