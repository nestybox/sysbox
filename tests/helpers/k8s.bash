#!/bin/bash

load ../helpers/run
load ../helpers/docker
load ../helpers/fs

#
# K8s Test Helper Functions
# (for tests using bats)
#

# NOTE: The K8s version must match that used in the K8s-node container image.
K8S_VERSION=v1.18.2

function kubeadm_get_token() {
  local k8s_master=$1
  local join=$(__docker exec $k8s_master sh -c "kubeadm token create --print-join-command 2> /dev/null")
  echo $join
}

function kubectl_config() {
  local node=$1
  docker exec "$node" sh -c "mkdir -p /root/.kube"
  [ "$status" -eq 0 ]
  docker exec "$node" sh -c "cp -i /etc/kubernetes/admin.conf /root/.kube/config"
  [ "$status" -eq 0 ]
  docker exec "$node" sh -c "chown $(id -u):$(id -g) /root/.kube/config"
  [ "$status" -eq 0 ]
}

function flannel_config() {
  local k8s_master=$1
  docker exec "$k8s_master" sh -c "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
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

  local req_storage=$((6*1024*1024*1024))
  local avail_storage=$(fs_avail "/")
  [ "$avail_storage" -ge "$req_storage" ]
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

# Determines pod readiness (Running) state.
#  $1 - k8s node to extract info from
#  $2 - k8s pod to query
#  $3 - k8s namespace where pod is expected (optional)
function k8s_pod_ready() {
  local k8s_master=$1
  local pod=$2

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

# Determines readiness (Running) state of all pods within array.
#  $1 - k8s node to extract info from
#  $2 - array of k8s pod to query
#  $3 - k8s namespace where pods are expected (optional)
function k8s_pod_array_ready() {
  local k8s_master=$1
  local pod_array=$2
  local pod

  if [ $# -eq 3 ]; then
     local ns="$3"
  fi

  for pod in "${pod_array[@]}"; do
    k8s_pod_ready ${k8s_master} ${pod} ${ns}
    if [ "$?" -ne 0 ]; then
      return 1
    fi
  done

  return 0
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

function k8s_cluster_is_clean() {
  local k8s_master=$1

  docker exec "$k8s_master" sh -c "kubectl get all"
  [ "$status" -eq 0 ]

  # Looking for:
  #
  # NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
  # service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   24m

  [ "${#lines[@]}" -eq "2" ]
  echo ${lines[1]} | grep -q "service/kubernetes"
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

  local k8s_master_id=$(docker_run --rm --network=$net --name=$k8s_master --hostname=$k8s_master nestybox/k8s-node-test:latest)

  wait_for_inner_dockerd $k8s_master

  docker exec $k8s_master sh -c "kubeadm init --kubernetes-version=$K8S_VERSION --pod-network-cidr=$pod_net_cidr"
  [ "$status" -eq 0 ]
  local kubeadm_output=$output

  run sh -c "echo \"$kubeadm_output\" | grep -q \"Your Kubernetes control\-plane has initialized successfully\""
  [ "$status" -eq 0 ]

  kubectl_config $k8s_master

  # When the k8s cluster is on top of a docker user-defined network,
  # we need to modify the k8s coredns upstream forwarding to avoid DNS
  # loops (see sysbox issue #512).
  if [ "$net" != "bridge" ]; then
    docker exec $k8s_master kubectl -n kube-system patch configmap/coredns -p '{"data":{"Corefile": ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 8.8.8.8\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'
  fi

  flannel_config $k8s_master

  retry_run 40 2 "k8s_node_ready $k8s_master $k8s_master"

  #
  # Deploy the K8s worker nodes (k8s-worker-<num>)
  #

  declare -a k8s_worker
  local worker_name
  local kubeadm_join=$(kubeadm_get_token $k8s_master)

  local i
  for (( i=0; i<$num_workers; i++ )); do
    worker_name=${cluster_name}-worker-${i}

    k8s_worker[$i]=$(docker_run --network=$net --rm --name=$worker_name --hostname=$worker_name nestybox/k8s-node-test:latest)
    wait_for_inner_dockerd ${k8s_worker[$i]}

    docker exec -d "${k8s_worker[$i]}" sh -c "$kubeadm_join"
    [ "$status" -eq 0 ]
  done

  for (( i=0; i<$num_workers; i++ )); do
    worker_name=${cluster_name}-worker-${i}
    retry_run 40 2 "k8s_node_ready $k8s_master $worker_name"
  done
}

# Tears-down a k8s cluster created with k8s_cluster_setup().
#
# usage: k8s_cluster_teardown cluster_name num_workers
function k8s_cluster_teardown() {
  local cluster_name=$1
  local num_workers=$2

  local k8s_master=${cluster_name}-master
  local worker_name

  local i
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
  docker exec "$k8s_master" sh -c "kubectl get pods -o wide --all-namespaces | egrep \"tiller\""
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  local tiller_pod=$(echo ${output} | awk '{print $2}')

  # Wait till tiller's pod is up and running.
  retry_run 60 5 "k8s_pod_ready $k8s_master $tiller_pod kube-system"
}

# Uninstall Helm v2.
function helm_v2_uninstall() {
  local k8s_master=$1

  # Obtain tiller's pod-name.
  docker exec "$k8s_master" sh -c "kubectl get pods -o wide --all-namespaces | egrep \"tiller\""
  [ "$status" -eq 0 ]
  local tiller_pod=$(echo ${lines[0]} | awk '{print $2}')

  # Delete all tiller's deployments.
  docker exec "$k8s_master" sh -c "kubectl delete deployment tiller-deploy --namespace kube-system"
  [ "$status" -eq 0 ]

  # Wait till tiller pod is fully destroyed.
  retry_run 40 2 "[ ! $(k8s_pod_ready $k8s_master $tiller_pod kube-system) ]"
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
    istioctl verify-install && \
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
  docker exec "$k8s_master" sh -c "kubectl delete ns istio-system"
  [ "$status" -eq 0 ]

  docker exec "$k8s_master" sh -c "kubectl label namespace default istio-injection-"
  [ "$status" -eq 0 ]

  # Remove installation script
  docker exec "$k8s_master" sh -c "rm -rf istio-*"
  [ "$status" -eq 0 ]
}

# Verifies an nginx ingress controller works; this function assumes
# the nginx ingress-controller has been deployed to the cluster.
function verify_nginx_ingress() {
  local k8s_master=$1
  local ing_controller=$2

  # We need pods to serve our fake website / service; we use an nginx
  # server pod and create a service in front of it (note that we could
  # have chosen any other pod for this purpose); the nginx ingress
  # controller will redirect traffic to these pods.
  docker exec $k8s_master sh -c "kubectl create deployment nginx --image=nginx:1.16-alpine"
  [ "$status" -eq 0 ]

  docker exec $k8s_master sh -c "kubectl expose deployment/nginx --port 80"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $k8s_master default nginx"

  # create an ingress rule that maps nginx.nestykube -> nginx service;
  # this ingress rule is enforced by the nginx ingress controller.
cat > "$test_dir/nginx-ing.yaml" <<EOF
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

  # apply the ingress rule
  docker cp $test_dir/nginx-ing.yaml $k8s_master:/root/nginx-ing.yaml
  [ "$status" -eq 0 ]

  docker exec $k8s_master sh -c "kubectl apply -f /root/nginx-ing.yaml"
  [ "$status" -eq 0 ]

  # setup the ingress hostname in /etc/hosts
  cp /etc/hosts /etc/hosts.orig
  local node_ip=$(k8s_node_ip k8s-worker-1)
  echo "$node_ip nginx.nestykube" >> /etc/hosts

  # verify ingress to nginx works
  sleep 1

  docker exec $k8s_master sh -c "kubectl get service/$ing_controller -o json | jq '.spec.ports[0].nodePort'"
  [ "$status" -eq 0 ]
  local nodePort=$output

  retry_run 10 2 "wget nginx.nestykube:$nodePort -O $test_dir/index.html"

  grep "Welcome to nginx" $test_dir/index.html
  rm $test_dir/index.html

  # Cleanup
  docker exec $k8s_master sh -c "kubectl delete ing nginx"
  [ "$status" -eq 0 ]
  docker exec $k8s_master sh -c "kubectl delete svc nginx"
  [ "$status" -eq 0 ]
  docker exec $k8s_master sh -c "kubectl delete deployment nginx"
  [ "$status" -eq 0 ]

  # "cp + rm" because "mv" fails with "resource busy" as /etc/hosts is
  # a bind-mount inside the container
  cp /etc/hosts.orig /etc/hosts
  rm /etc/hosts.orig
}
