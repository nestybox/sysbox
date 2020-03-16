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
  local k8s_master=$1
  docker exec "$k8s_master" sh -c "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
  [ "$status" -eq 0 ]
}

function k8s_node_ready() {
  local k8s_master=$1
  local node=$2
  local i

  docker exec "$k8s_master" sh -c "kubectl get node $node"
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
  local k8s_master=$1
  local pod=$2
  local i

  if [ $# -eq 3 ]; then
     local ns="-n $3"
  fi

  docker exec "$k8s_master" sh -c "kubectl get pod $pod $ns"
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
  local k8s_master=$1
  local pod=$2

  docker exec "$k8s_master" sh -c "kubectl get pod $pod -o wide"
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"
  echo $pod_status | awk '{print $6}'
}

# Returns the node associated with a given pod
function k8s_pod_node() {
  local k8s_master=$1
  local pod=$2

  docker exec "$k8s_master" sh -c "kubectl get pod $pod -o wide"
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"
  echo $pod_status | awk '{print $7}'
}

# Checks if a pod is scheduled on a given node
function k8s_pod_in_node() {
  local k8s_master=$1
  local pod=$2
  local node=$3

  docker exec "$k8s_master" sh -c "kubectl get pod $pod -o wide"
  [ "$status" -eq 0 ]

  local cur_node=$(echo "${lines[1]}" | awk '{print $7}')

  [[ $cur_node == $node ]]
}

# Returns the IP address associated with a given service
function k8s_svc_ip() {
  local k8s_master=$1
  local ns=$2
  local svc=$3

 docker exec "$k8s_master" sh -c "kubectl --namespace $ns get svc $svc"
  [ "$status" -eq 0 ]

  local svc_status="${lines[1]}"
  echo $svc_status | awk '{print $3}'
}

function k8s_check_proxy_mode() {
  local k8s_master=$1
  local proxy_mode=$2

  docker exec "$k8s_master" sh -c "docker ps | grep kube-proxy | grep -v pause | awk '{print \$1}'"
  [ "$status" -eq 0 ]

  local kube_proxy=$output

  docker exec "$k8s_master" sh -c "docker logs $kube_proxy 2>&1 | grep \"Using $proxy_mode Proxier\""
  [ "$status" -eq 0 ]
}

function k8s_deployment_ready() {
  local k8s_master=$1
  local ns=$2
  local deployment=$3

  docker exec "$k8s_master" sh -c "kubectl --namespace $ns get deployment $deployment"
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
  local k8s_master=$1
  local ns=$2
  local deployment=$3
  local i

  docker exec "$k8s_master" sh -c "kubectl --namespace $ns rollout status deployment.v1.apps/$deployment"
  [ "$status" -eq 0 ]
  [[ "$output" == "deployment \"$deployment\" successfully rolled out" ]]
}

function k8s_daemonset_ready() {
  local k8s_master=$1
  local ns=$2
  local ds=$3

  docker exec "$k8s_master" sh -c "kubectl --namespace $ns get ds $ds"
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
# usage: k8s_cluster_setup cluster_name num_workers network
#
# cluster_name: name of the cluster; nodes in the cluster are named "<cluster_name>-master",
#               "<cluster-name>-worker-0", "<cluster-name>-worker-1", etc.
# num_workers: number of k8s worker nodes
# network: docker network to which the k8s nodes are connected (e.g., bridge, user-defined, etc.)

function k8s_cluster_setup() {
  local cluster_name=$1
  local num_workers=$2
  local net=$3

  local k8s_master=${cluster_name}-master
  local pod_net_cidr=10.244.0.0/16

  #
  # Deploy the master node
  #

  docker_run --rm --network=$net --name=$k8s_master --hostname=$k8s_master nestybox/ubuntu-bionic-k8s:latest

  wait_for_inner_dockerd $k8s_master

  docker exec $k8s_master sh -c "kubeadm init --kubernetes-version=v1.17.2 --pod-network-cidr=$pod_net_cidr"
  [ "$status" -eq 0 ]
  local kubeadm_output=$output

  run sh -c "echo \"$kubeadm_output\" | grep -q \"Your Kubernetes control\-plane has initialized successfully\""
  [ "$status" -eq 0 ]

  run sh -c "echo \"$kubeadm_output\" | grep -A1 \"kubeadm join\""
  [ "$status" -eq 0 ]
  local kubeadm_join=$output

  kubectl_config $k8s_master

  # When the k8s cluster is on top of a docker user-defined network,
  # we need to modify the k8s coredns upstream forwarding to avoid DNS
  # loops (see sysbox issue #512).
  if [ "$net" != "bridge" ]; then
    docker exec $k8s_master kubectl -n kube-system patch configmap/coredns -p '{"data":{"Corefile": ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 8.8.8.8\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'
  fi

  flannel_config $k8s_master

  retry_run 20 2 "k8s_node_ready $k8s_master $k8s_master"

  #
  # Deploy the K8s worker nodes (k8s-worker-<num>)
  #

  declare -a k8s_worker
  local name

  for (( i=0; i<$num_workers; i++ )); do
    worker_name=${cluster_name}-worker-${i}
    k8s_worker[$i]=$(docker_run --network=$net --rm --name=$worker_name --hostname=$worker_name nestybox/ubuntu-bionic-k8s:latest)
    wait_for_inner_dockerd ${k8s_worker[$i]}
  done

  for (( i=0; i<$num_workers; i++ )); do
    docker exec -d "${k8s_worker[$i]}" sh -c "$kubeadm_join"
    [ "$status" -eq 0 ]
  done

  for (( i=0; i<$num_workers; i++ )); do
    worker_name=${cluster_name}-worker-${i}
    retry_run 40 2 "k8s_node_ready $k8s_master $worker_name"
  done

  echo $kubeadm_join
}

# Tears-down a k8s cluster created with k8s_cluster_setup().
#
# usage: k8s_cluster_teardown cluster_name num_workers
function k8s_cluster_teardown() {
  local cluster_name=$1
  local num_workers=$2

  local k8s_master=${cluster_name}-master
  local worker_name

  for i in `seq 0 $(( $num_workers - 1 ))`; do
    worker_name=${cluster_name}-worker-${i}
    docker_stop $worker_name
  done

  docker_stop $k8s_master
}

# Install Helm v2.
function helm_v2_install() {
  local k8s_master=$1

  docker exec "$k8s_master" sh -c "curl -Os https://get.helm.sh/helm-v2.16.3-linux-amd64.tar.gz && \
    tar -zxvf helm-v2.16.3-linux-amd64.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    kubectl create serviceaccount --namespace kube-system tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'      
    helm init --service-account tiller --upgrade
    helm repo add stable https://kubernetes-charts.storage.googleapis.com/ && \
    helm repo update"
  [ "$status" -eq 0 ]

  sleep 5

  # Identify tiller's pod name.
  docker exec k8s-master sh -c "kubectl get pods -o wide --all-namespaces | egrep \"tiller\""
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  local tiller_pod=$(echo ${output} | awk '{print $2}')

  # Wait till tiller's pod is up and running.
  retry_run 60 5 "k8s_pod_ready k8s-master $tiller_pod kube-system"  
}

# Uninstall Helm v2.
function helm_v2_uninstall() {
  local k8s_master=$1
  
  # Obtain tiller's pod-name.
  docker exec k8s-master sh -c "kubectl get pods -o wide --all-namespaces | egrep \"tiller\""
  [ "$status" -eq 0 ]
  local tiller_pod=$(echo ${lines[0]} | awk '{print $2}')
  
  # Delete all tiller's deployments.
  docker exec "$k8s_master" sh -c "kubectl delete deployment tiller-deploy --namespace kube-system"
  [ "$status" -eq 0 ]

  # Wait till tiller pod is fully destroyed.
  retry_run 20 2 "[ ! $(k8s_pod_ready k8s-master $tiller_pod kube-system) ]"
}

# Uninstall Helm v3. Right, much simpler than v2 version above, as there's no need to
# deal with 'tiller' complexities.
function helm_v3_install() {
  local k8s_master=$1

  docker exec "$k8s_master" sh -c "curl -Os https://get.helm.sh/helm-v3.1.2-linux-amd64.tar.gz && \
    tar -zxvf helm-v3.1.2-linux-amd64.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    helm repo add stable https://kubernetes-charts.storage.googleapis.com/ && \
    helm repo update"
  [ "$status" -eq 0 ]
}

# Uninstall Helm v3.
function helm_v3_uninstall() {
  local k8s_master=$1
  docker exec "$k8s_master" sh -c "helm reset"
}