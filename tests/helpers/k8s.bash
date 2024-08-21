#!/usr/bin/env bats

load $(dirname ${BASH_SOURCE[0]})/run.bash
load $(dirname ${BASH_SOURCE[0]})/docker.bash
load $(dirname ${BASH_SOURCE[0]})/systemd.bash
load $(dirname ${BASH_SOURCE[0]})/fs.bash

#
# K8s Test Helper Functions
# (for tests using bats)
#

function kubeadm_get_token() {
  local k8s_master=$1
  local join=$(__docker exec $k8s_master sh -c "kubeadm token create --print-join-command 2> /dev/null")
  echo $join
}

# Sets up a proper k8s config in the node being passed.
function k8s_config() {
  local node=$1

  docker exec "$node" sh -c "mkdir -p /root/.kube && \
    cp -i /etc/kubernetes/admin.conf /root/.kube/config && \
    chown $(id -u):$(id -g) /root/.kube/config"
  [ "$status" -eq 0 ]
}

# Checks that the host has sufficient storage to run K8s clusters
function k8s_check_sufficient_storage() {

  # K8s requires nodes to have a decent amount of storage (otherwise the
  # kubelet refuses to deploy pods on the node). Here, we specify that
  # we need 6GB (~1.8GB for the k8s node image, plus plenty room for
  # inner containers).
  #
  # Note that Sysbox does not yet support virtualizing the storage
  # space allocated to the K8s node sys-container, so each node sees
  # the storage space of the host.

  local req_storage=$((6 * 1024 * 1024 * 1024))
  local avail_storage=$(fs_avail "/")
  [ "$avail_storage" -ge "$req_storage" ]
}

function k8s_node_ready() {
  local node=$1

  ret=$(kubectl get node $node | tail -n 1)
  if [ $? -ne 0 ]; then
    return 1
  fi

  echo $ret | awk '{print $2}' | grep -qw Ready
}

function k8s_node_ip() {
  local node=$1
  docker_cont_ip $node
}

function k8s_apply() {
  local yaml=$1

  run kubectl apply -f $yaml
  [ "$status" -eq 0 ]
}

function k8s_delete() {
  local yaml=$1

  run kubectl delete -f $yaml
  [ "$status" -eq 0 ]
}

function k8s_create_pod() {
  local pod_yaml=$1

  run kubectl apply -f $pod_yaml
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}

function k8s_del_pod() {
  local pod=$1
  local ns=""

  if [ $# -eq 2 ]; then
    ns="-n $2"
  fi

  run kubectl delete pod $pod $ns --grace-period=0
  [ "$status" -eq 0 ]
}

# Determines pod readiness (Running) state.
#  $1 - k8s pod to query
#  $2 - k8s namespace where pod is expected (optional)
function k8s_pod_ready() {
  local pod=$1
  local ns=""

  if [ $# -eq 2 ]; then
    ns="-n $2"
  fi

  run kubectl get pod $pod $ns
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"

  # Looking for:
  #
  # NAME    READY   STATUS   RESTARTS
  # pod     x/x     Running  0

  local total=$(sh -c "echo '$pod_status' | awk '{print \$2}' | cut -d \"/\" -f 2")
  echo "$pod_status" | awk -v OFS=' ' '{print $1, $2, $3, $4}' | egrep -q "$pod $total/$total Running 0"
}

# Determines readiness (Running) state of all pods within array.
#  $1 - array of k8s pod to query
function k8s_pod_array_ready() {
  local pod_array=("$@")
  local pod

  for pod in "${pod_array[@]}"; do
    k8s_pod_ready $pod $ns
    if [ $? -ne 0 ]; then
      return 1
    fi
  done

  return 0
}

# Verify if all the pods of a given namespace have been fully initialized (i.e.,
# "running" or "completed" state).
# $1 - k8s namespace (optional)
function k8s_all_pods_ready() {
  local ns=""

  if [ $# -eq 1 ]; then
    ns="-n $1"
  fi

  run sh -c "kubectl get pods $ns -o wide | awk 'NR>1' | wc -l"
  [ "$status" -eq 0 ]
  echo "status = $status"
  echo "pods_count = $output"
  local pods_count=$output

  run sh -c "kubectl get pods $ns -o wide | awk 'NR>1' | egrep "Running | Completed" | wc -l"
  [ "$status" -eq 0 ]
  echo "status = $status"
  echo "running_pods_count = $output"
  local running_pods_count=$output
  [ "$running_pods_count" -eq "$pods_count" ]
}

function k8s_pod_absent() {
  local pod=$1
  local ns=""

  if [ $# -eq 2 ]; then
    ns="-n $2"
  fi

  run kubectl get pod $pod $ns
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 1 ]
}

# Returns the IP address associated with a given pod
function k8s_pod_ip() {
  local pod=$1

  run kubectl get pod $pod -o wide
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"
  echo $pod_status | awk '{print $6}'
}

# Returns the node associated with a given pod
function k8s_pod_node() {
  local pod=$1

  run kubectl get pod $pod -o wide
  [ "$status" -eq 0 ]

  local pod_status="${lines[1]}"
  echo $pod_status | awk '{print $7}'
}

# Checks if a pod is scheduled on a given node
function k8s_pod_in_node() {
  local pod=$1
  local node=$2

  # TODO: Find out why function doesn't behave as expected when using 'kubectl'
  # instead of 'docker exec' instruction; ideally, we want to avoid using
  # 'docker exec' here.
  run kubectl get pod "$pod" -o wide
  [ "$status" -eq 0 ]

  local cur_node=$(echo "${lines[1]}" | awk '{print $7}')

  [[ "$cur_node" == "$node" ]]
}

# Returns the IP address associated with a given service
function k8s_svc_ip() {
  local ns=$1
  local svc=$2

  run kubectl --namespace $ns get svc $svc
  [ "$status" -eq 0 ]

  local svc_status="${lines[1]}"
  echo $svc_status | awk '{print $3}'
}

function k8s_check_proxy_mode() {
  local proxy_mode=$1

  run sh -c "kubectl -n kube-system get pods | grep -m 1 kube-proxy | awk '{print \$1}'"
  echo "status1 = ${status}"
  echo "output1 = ${output}"
  [ "$status" -eq 0 ]

  local kube_proxy=$output

  run sh -c "kubectl -n kube-system logs $kube_proxy 2>&1 | grep \"Using $proxy_mode Proxier\""
  echo "status2 = ${status}"
  echo "output2 = ${output}"
  [ "$status" -eq 0 ]
}

function k8s_deployment_ready() {
  local ns=$1
  local deployment=$2

  kubectl --namespace $ns get deployment $deployment
  [ "$status" -eq 0 ]

  local dpl_status="${lines[1]}"

  # Looking for:
  #
  # NAME    READY   UP-TO-DATE   AVAILABLE
  # name    x/x     1            1

  local total=$(sh -c "echo $dpl_status | awk '{print \$2}' | cut -d \"/\" -f 2")
  echo $dpl_status | awk -v OFS=' ' '{print $1, $2, $3, $4}' | grep -q "$deployment $total/$total $total $total"
}

function k8s_deployment_rollout_ready() {
  local ns=$1
  local deployment=$2

  kubectl --namespace $ns rollout status deployment.v1.apps/$deployment
  [ "$status" -eq 0 ]
  [[ "$output" == "deployment \"$deployment\" successfully rolled out" ]]
}

function k8s_daemonset_ready() {
  local ns=$1
  local ds=$2

  kubectl --namespace $ns get ds $ds
  [ "$status" -eq 0 ]

  local dpl_status="${lines[1]}"

  # Looking for:
  #
  # NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
  # $ds     2         2         2       2            2

  local total=$(echo $dpl_status | awk '{print $2}')
  echo $dpl_status | awk -v OFS=' ' '{print $1, $2, $3, $4, $5, $6}' | grep "$ds $total $total $total $total $total"
}

function k8s_cluster_is_clean() {

  run kubectl get all
  [ "$status" -eq 0 ]

  # Looking for:
  #
  # NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
  # service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   24m

  [ "${#lines[@]}" -eq "2" ]
  echo ${lines[1]} | grep -q "service/kubernetes"
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
  run sh -c "kubectl get pods -o wide --all-namespaces | egrep \"tiller\""
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  local tiller_pod=$(echo ${output} | awk '{print $2}')

  # Wait till tiller's pod is up and running.
  retry_run 60 5 "k8s_pod_ready $tiller_pod kube-system"
}

# Uninstall Helm v2.
function helm_v2_uninstall() {

  # Obtain tiller's pod-name.
  run sh -c "kubectl get pods -o wide --all-namespaces | egrep \"tiller\""
  [ "$status" -eq 0 ]
  local tiller_pod=$(echo ${lines[0]} | awk '{print $2}')

  # Delete all tiller's deployments.
  run kubectl delete deployment tiller-deploy --namespace kube-system
  [ "$status" -eq 0 ]

  # Wait till tiller pod is fully destroyed.
  retry_run 40 2 "k8s_pod_absent $tiller_pod kube-system"
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

# Installs Istio.
function istio_install() {
  local k8s_master=$1

  # Bear in mind that the Istio version to download has not been explicitly defined,
  # which has its pros (test latest releases) & cons (test instability).
  docker exec "$k8s_master" sh -c "curl -L https://istio.io/downloadIstio | sh - && \
    cp istio*/bin/istioctl /usr/local/bin/ && \
    istioctl manifest apply --set profile=demo && \
    kubectl label namespace default istio-injection=enabled"
  [ "$status" -eq 0 ]
}

# Uninstalls Istio.
function istio_uninstall() {
  local k8s_master=$1

  # Run uninstallation script.
  docker exec "$k8s_master" sh -c "istio-*/samples/bookinfo/platform/kube/cleanup.sh"
  [ "$status" -eq 0 ]

  # Remove istio namespace.
  run kubectl delete ns istio-system
  [ "$status" -eq 0 ]

  run kubectl label namespace default istio-injection-
  [ "$status" -eq 0 ]

  # Remove installation script
  docker exec "$k8s_master" sh -c "rm -rf istio-*"
  [ "$status" -eq 0 ]
}

# Verifies an nginx ingress controller works; this function assumes
# the nginx ingress-controller has been deployed to the cluster.
function verify_nginx_ingress() {
  local ing_controller=$1
  local ing_worker_node=$2

  # We need pods to serve our fake website / service; we use an nginx
  # server pod and create a service in front of it (note that we could
  # have chosen any other pod for this purpose); the nginx ingress
  # controller will redirect traffic to these pods.
  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.16-alpine
  [ "$status" -eq 0 ]

  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready default nginx"

  # create an ingress rule that maps nginx.nestykube -> nginx service;
  # this ingress rule is enforced by the nginx ingress controller.
  cat >"$test_dir/nginx-ing.yaml" <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: nginx.nestykube
    http:
      paths:
      - path: /
        backend:
          serviceName: nginx
          servicePort: 80
EOF

  run kubectl apply -f $test_dir/nginx-ing.yaml
  [ "$status" -eq 0 ]

  # setup the ingress hostname in /etc/hosts
  cp /etc/hosts /etc/hosts.orig
  local node_ip=$(k8s_node_ip ${ing_worker_node})
  echo "$node_ip nginx.nestykube" >>/etc/hosts

  # verify ingress to nginx works
  sleep 1

  run sh -c "kubectl get service/$ing_controller -o json | jq '.spec.ports[0].nodePort'"
  [ "$status" -eq 0 ]
  local nodePort=$output

  retry_run 10 2 "wget nginx.nestykube:$nodePort -O $test_dir/index.html"

  grep "Welcome to nginx" $test_dir/index.html
  rm $test_dir/index.html

  # Cleanup
  run kubectl delete ing nginx
  [ "$status" -eq 0 ]
  run kubectl delete svc nginx
  [ "$status" -eq 0 ]
  run kubectl delete deployment nginx
  [ "$status" -eq 0 ]

  # "cp + rm" because "mv" fails with "resource busy" as /etc/hosts is
  # a bind-mount inside the container
  cp /etc/hosts.orig /etc/hosts
  rm /etc/hosts.orig
}

################################################################################
# KinD specific functions
################################################################################

function kind_all_nodes_ready() {
  local cluster=$1
  local num_workers=$2
  local delay=$3

  local timestamp=$(date +%s)
  local timeout=$(($timestamp + $delay))
  local all_ok

  while [ $timestamp -lt $timeout ]; do
    all_ok="true"

    for i in $(seq 1 $num_workers); do
      local worker
      if [ $i -eq 1 ]; then
        worker="${cluster}"-worker
      else
        worker="${cluster}"-worker$i
      fi

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

################################################################################
# KindBox specific functions
################################################################################

function kindbox_all_nodes_ready() {
  local cluster_name=$1
  local num_workers=$2
  local delay=$3

  local timestamp=$(date +%s)
  local timeout=$(($timestamp + $delay))
  local all_ok

  while [ $timestamp -lt $timeout ]; do
    all_ok="true"

    for ((i = 0; i < $num_workers; i++)); do
      master=${cluster_name}-master
      worker=${cluster_name}-worker-${i}

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

# Deploys a k8s cluster through KindBox tool. The cluster has one master node
# and the given number of worker nodes. The cluster uses the K8s flannel cni.
# The master node sys container is called k8s-master and the worker nodes are
# called k8s-worker-0, k8s-worker-1, etc.
#
# usage: k8s_cluster_setup <cluster_name> <num_workers> <network> <node_image> <k8s_version>
#
# cluster: name of the cluster; nodes in the cluster are named "<cluster_name>-master",
#          "<cluster-name>-worker-0", "<cluster-name>-worker-1", etc.
# num_workers: number of k8s worker nodes
# network: docker network to which the k8s nodes are connected (e.g., bridge,
#          user-defined, etc.)
function kindbox_cluster_setup() {
  local cluster=$1
  local num_workers=$2
  local net=$3
  local node_image=$4
  local k8s_version=$5
  local cni=$6

  local pod_net_cidr=10.244.0.0/16

  if [[ ${cni} == "" ]]; then
    run tests/scr/kindbox create --num=$num_workers --image=$node_image --k8s-version=$k8s_version --net=$net $cluster
    [ "$status" -eq 0 ]
  else
    run tests/scr/kindbox create --num=$num_workers --image=$node_image --k8s-version=$k8s_version --net=$net --cni=$cni $cluster
    [ "$status" -eq 0 ]
  fi

  local join_timeout=$(($num_workers * 30))

  kindbox_all_nodes_ready $cluster $num_workers $join_timeout
}

# Tears-down a k8s cluster created with kindbox_cluster_setup().
#
# usage: kindbox_cluster_teardown cluster_name num_workers
function kindbox_cluster_teardown() {
  local cluster=$1
  local net=$2

  if [[ $net == "bridge" ]]; then
    run tests/scr/kindbox destroy $cluster
    [ "$status" -eq 0 ]
  else
    run tests/scr/kindbox destroy --net $cluster
    [ "$status" -eq 0 ]
  fi

  # Delete cluster config.
  rm -rf /root/.kube/${cluster}-config
}
