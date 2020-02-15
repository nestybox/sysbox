#!/bin/bash

load ../helpers/run
load ../helpers/docker

#
# K8s Test Helper Functions
#
# Note: for tests using bats.
#

function kubectl_config() {
  local node=$1
  docker exec "$node" sh -c "mkdir -p $HOME/.kube"
  [ "$status" -eq 0 ]
  docker exec "$node" sh -c "cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
  [ "$status" -eq 0 ]
  docker exec "$node" sh -c "chown $(id -u):$(id -g) $HOME/.kube/config"
  [ "$status" -eq 0 ]
}

function flannel_config() {
  local master=$1
  docker exec "$master" sh -c "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
  [ "$status" -eq 0 ]
}

function k8s_node_ready() {
  local master=$1
  local node=$2
  local i

  docker exec "$master" sh -c "kubectl get node $node"
  [ "$status" -eq 0 ]

  echo ${lines[1]} | awk '{print $2}' | grep -qw "Ready"
}

function k8s_node_ip() {
  local node=$1
  docker_cont_ip $node
}

function k8s_apply() {
  local k8s_master=$1
  local yaml=$2

  docker cp $yaml "$k8s_master:/root/tmp.yaml"
  [ "$status" -eq 0 ]

  docker exec "$k8s_master" sh -c "kubectl apply -f /root/tmp.yaml"
  [ "$status" -eq 0 ]

  docker exec "$k8s_master" sh -c "rm -rf /root/tmp.yaml"
  [ "$status" -eq 0 ]
}

function k8s_create_pod() {
  local k8s_master=$1
  local pod_yaml=$2

  k8s_apply $k8s_master $pod_yaml
}

function k8s_del_pod() {
  local k8s_master=$1
  local pod=$2

  docker exec "$k8s_master" sh -c "kubectl delete pod $pod --grace-period=0"
  [ "$status" -eq 0 ]
}

function k8s_pod_ready() {
  local master=$1
  local pod=$2
  local i

  docker exec "$master" sh -c "kubectl get pod $pod"
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"

  # Looking for:
  #
  # NAME    READY   STATUS   RESTARTS
  # pod     x/x     Running  0

  local total=$(sh -c "echo $pod_status | awk '{print \$2}' | cut -d \"/\" -f 2")
  echo $pod_status | awk -v OFS=' ' '{print $1, $2, $3, $4}' | grep -q "$pod $total/$total Running 0"
}

# Returns the IP address associated with a given pod
function k8s_pod_ip() {
  local master=$1
  local pod=$2

  docker exec "$master" sh -c "kubectl get pod $pod -o wide"
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"
  echo $pod_status | awk '{print $6}'
}

# Returns the node associated with a given pod
function k8s_pod_node() {
  local master=$1
  local pod=$2

  docker exec "$master" sh -c "kubectl get pod $pod -o wide"
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"
  echo $pod_status | awk '{print $7}'
}

# Checks if a pod is scheduled on a given node
function k8s_pod_in_node() {
  local master=$1
  local pod=$2
  local node=$3

  docker exec "$master" sh -c "kubectl get pod $pod -o wide"
  [ "$status" -eq 0 ]

  local cur_node=$(echo "${lines[1]}" | awk '{print $7}')

  [[ $cur_node == $node ]]
}

# Returns the IP address associated with a given service
function k8s_svc_ip() {
  local master=$1
  local ns=$2
  local svc=$3

 docker exec "$master" sh -c "kubectl --namespace $ns get svc $svc"
  [ "$status" -eq 0 ]

  local svc_status="${lines[1]}"
  echo $svc_status | awk '{print $3}'
}

function k8s_check_proxy_mode() {
  local master=$1
  local proxy_mode=$2

  docker exec "$master" sh -c "docker ps | grep kube-proxy | grep -v pause | awk '{print \$1}'"
  [ "$status" -eq 0 ]

  local kube_proxy=$output

  docker exec "$master" sh -c "docker logs $kube_proxy 2>&1 | grep \"Using $proxy_mode Proxier\""
  [ "$status" -eq 0 ]
}

function k8s_deployment_ready() {
  local master=$1
  local ns=$2
  local deployment=$3

  docker exec "$master" sh -c "kubectl --namespace $ns get deployment $deployment"
  [ "$status" -eq 0 ]

  local dpl_status="${lines[1]}"

  # Looking for:
  #
  # NAME    READY   UP-TO-DATE   AVAILABLE
  # name    x/x     1            1

  local total=$(sh -c "echo $dpl_status | awk '{print \$2}' | cut -d \"/\" -f 2")
  echo $dpl_status | awk -v OFS=' ' '{print $1, $2, $3, $4}' | grep "$deployment $total/$total $total $total"
}

function k8s_deployment_rollout_ready() {
  local master=$1
  local ns=$2
  local deployment=$3
  local i

  docker exec "$master" sh -c "kubectl --namespace $ns rollout status deployment.v1.apps/$deployment"
  [ "$status" -eq 0 ]
  [[ "$output" == "deployment \"$deployment\" successfully rolled out" ]]
}

function k8s_daemonset_ready() {
  local master=$1
  local ns=$2
  local ds=$3

  docker exec "$master" sh -c "kubectl --namespace $ns get ds $ds"
  [ "$status" -eq 0 ]

  local dpl_status="${lines[1]}"

  # Looking for:
  #
  # NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
  # $ds     2         2         2       2            2

  local total=$(echo $dpl_status | awk '{print $2}')
  echo $dpl_status | awk -v OFS=' ' '{print $1, $2, $3, $4, $5, $6}' | grep "$ds $total $total $total $total $total"
}


# Deploys a k8s cluster using sys containers; the cluster has one
# master node and the given number of worker nodes. The cluster uses
# the K8s flannel cni. The master node sys container is called
# k8s-master and the worker nodes are called k8s-worker-0,
# k8s-worker-1, etc.
#
# This function returns the "kubeadm join" string (in case the caller
# wants to add more nodes need to be added to the cluster).
#
# usage: k8s_cluster_setup num_workers network
#
# num_workers: number of k8s worker nodes
# network: docker network to which the k8s nodes are connected (e.g., bridge, user-defined, etc.)

function k8s_cluster_setup() {
  local num_workers=$1
  local net=$2
  local pod_net_cidr=10.244.0.0/16

  #
  # Deploy the master node (k8s-master)
  #

  docker_run --rm --network=$net --name=k8s-master --hostname=k8s-master nestybox/ubuntu-bionic-k8s:latest

  wait_for_inner_dockerd k8s-master

  docker exec k8s-master sh -c "kubeadm init --pod-network-cidr=$pod_net_cidr"
  [ "$status" -eq 0 ]
  local kubeadm_output=$output

  run sh -c "echo \"$kubeadm_output\" | grep -q \"Your Kubernetes control\-plane has initialized successfully\""
  [ "$status" -eq 0 ]

  run sh -c "echo \"$kubeadm_output\" | grep -A1 \"kubeadm join\""
  [ "$status" -eq 0 ]
  local kubeadm_join=$output

  kubectl_config k8s-master

  # When the k8s cluster is on top of a docker user-defined network,
  # we need to modify the k8s coredns upstream forwarding to avoid DNS
  # loops (see sysbox issue #512).
  if [ "$net" != "bridge" ]; then
    docker exec k8s-master kubectl -n kube-system patch configmap/coredns -p '{"data":{"Corefile": ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 8.8.8.8\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'
  fi

  flannel_config k8s-master

  retry_run 20 2 "k8s_node_ready k8s-master"

  #
  # Deploy the K8s worker nodes (k8s-worker-<num>)
  #

  declare -a k8s_worker

  for (( i=0; i<$num_workers; i++ )); do
    k8s_worker[$i]=$(docker_run --network=$net --rm --name="k8s-worker-$i" --hostname="k8s-worker-$i" nestybox/ubuntu-bionic-k8s:latest)
    wait_for_inner_dockerd ${k8s_worker[$i]}
  done

  for (( i=0; i<$num_workers; i++ )); do
    docker exec -d "${k8s_worker[$i]}" sh -c "$kubeadm_join"
    [ "$status" -eq 0 ]
  done

  for (( i=0; i<$num_workers; i++ )); do
    retry_run 40 1 "k8s_node-ready ${k8s_worker[$i]}"
  done

  echo $kubeadm_join
}

# Tears-down a k8s cluster created with k8s_cluster_setup().
function k8s_cluster_teardown() {
  local num_workers=$1

  for i in `seq 0 $(( $num_workers - 1 ))`; do
    local worker=k8s-worker-$i
    docker_stop $worker
  done

  docker_stop k8s-master
}
