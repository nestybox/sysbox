#!/usr/bin/env bats

# Tests for deploying a K8s cluster with custom bridge networks. The cluster
# will be launched by making use of KindBox tool.
#
# The system container nodes have K8s + Docker inside (i.e., K8s uses
# Docker to deploy pods).
#
# NOTE: the "cluster up" test must execute before all others,
# as it brings up the K8s cluster. Similarly, the "cluster down"
# test must execute after all other tests.

load ../helpers/run
load ../helpers/docker
load ../helpers/k8s
load ../helpers/sysbox-health

export test_dir="/tmp/k8s-test/"
export manifest_dir="tests/kind/manifests/"

# Cluster definition.
export cluster=cluster
export controller="${cluster}"-master
export net="${cluster}"-net
export num_workers=2

# Preset kubeconfig env-var to point to both cluster-configs.
export KUBECONFIG=${HOME}/.kube/${cluster}-config

# Cluster's node image.
export node_image="${CTR_IMG_REPO}/k8s-node-test:v1.20.2"


function teardown() {
  sysbox_log_check
}

function create_test_dir() {
  run mkdir -p "$test_dir"
  [ "$status" -eq 0 ]

  run rm -rf "$test_dir/*"
  [ "$status" -eq 0 ]
}

function remove_test_dir() {
  run rm -rf "$test_dir"
  [ "$status" -eq 0 ]
}

@test "kind custom net cluster up" {

  k8s_check_sufficient_storage

  create_test_dir

  # Create new cluster.
  kindbox_cluster_setup $cluster $num_workers $net $node_image

  # Switch to the cluster context just created.
  kubectl config use-context kubernetes-admin@"${cluster}"

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/.${cluster}_num_workers"
}

@test "kind deployment" {

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.16-alpine
  echo "status = ${status}"
  echo "output = ${output}"
  echo "kubeconfig = $(echo $KUBECONFIG)"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # scale up
  run kubectl scale --replicas=4 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # rollout new nginx image
  run kubectl set image deployment/nginx nginx=${CTR_IMG_REPO}/nginx:1.17-alpine --record
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_rollout_ready $cluster $controller default nginx"

  # scale down
  run kubectl scale --replicas=1 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # cleanup
  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]
}

@test "kind service clusterIP" {

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.17-alpine
  [ "$status" -eq 0 ]

  run kubectl scale --replicas=3 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # create a service and confirm it's there
  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  local svc_ip=$(k8s_svc_ip $cluster $controller default nginx)

  sleep 3

  docker exec $controller sh -c "curl -s $svc_ip | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # launch an pod in the same k8s namespace and verify it can access the service
  cat > /tmp/alpine-sleep.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: alpine-sleep
spec:
  containers:
  - name: alpine
    image: ${CTR_IMG_REPO}/alpine
    args:
    - sleep
    - "1000000"
EOF

  k8s_create_pod $cluster $controller /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready alpine-sleep"

  run kubectl exec alpine-sleep -- sh -c "apk add curl"
  [ "$status" -eq 0 ]

  run sh -c 'kubectl exec alpine-sleep -- sh -c "curl -s \$NGINX_SERVICE_HOST" | grep -q "Welcome to nginx"'
  [ "$status" -eq 0 ]

  # verify the kube-proxy is using iptables (does so by default)
  k8s_check_proxy_mode $cluster $controller iptables

  # verify k8s has programmed iptables inside the sys container net ns
  docker exec $controller sh -c "iptables -L | grep -q KUBE"
  [ "$status" -eq 0 ]

  # verify no k8s iptable chains are seen outside the sys container net ns
  iptables -L | grep -qv KUBE

  # cleanup
  k8s_del_pod alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kind service nodePort" {

  local num_workers=$(cat "$test_dir/.${cluster}_num_workers")

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.17-alpine
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # create a nodePort service
  run kubectl expose deployment/nginx --port 80 --type NodePort
  [ "$status" -eq 0 ]

  # get the node port for the service
  run sh -c 'kubectl get svc nginx -o json | jq .spec.ports[0].nodePort'
  [ "$status" -eq 0 ]
  svc_port=$output

  # verify the service is exposed on all nodes of the cluster
  node_ip=$(k8s_node_ip $controller)

  run sh -c "curl -s $node_ip:$svc_port | grep \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  for i in `seq 0 $(( $num_workers - 1 ))`; do
	  local worker=${cluster}-worker-$i
	  node_ip=$(k8s_node_ip $worker)
	  run sh -c "curl -s $node_ip:$svc_port | grep -q \"Welcome to nginx\""
	  [ "$status" -eq 0 ]
  done

  # verify we can access the service from within a pod in the cluster
  cat > /tmp/alpine-sleep.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: alpine-sleep
spec:
  containers:
  - name: alpine
    image: ${CTR_IMG_REPO}/alpine
    args:
    - sleep
    - "1000000"
EOF

  k8s_create_pod $cluster $controller /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready alpine-sleep"

  run kubectl exec alpine-sleep -- sh -c "apk add curl"
  [ "$status" -eq 0 ]

  run sh -c 'kubectl exec alpine-sleep -- sh -c "curl -s \$NGINX_SERVICE_HOST" | grep -q "Welcome to nginx"'
  [ "$status" -eq 0 ]

  # cleanup
  k8s_del_pod alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kind DNS clusterIP" {

  # launch a deployment with an associated service

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.17-alpine
  [ "$status" -eq 0 ]

  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  # launch a pod in the same k8s namespace
  cat > /tmp/alpine-sleep.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: alpine-sleep
spec:
  containers:
  - name: alpine
    image: ${CTR_IMG_REPO}/alpine
    args:
    - sleep
    - "1000000"
EOF

  k8s_create_pod $cluster $controller /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready alpine-sleep"

  # find the cluster's DNS IP address
  run sh -c "kubectl get services --all-namespaces -o wide | grep kube-dns | awk '{print \$4}'"
  [ "$status" -eq 0 ]
  local dns_ip=$output

  # verify the pod has the cluster DNS server in its /etc/resolv.conf
  run sh -c "kubectl exec alpine-sleep -- sh -c \"cat /etc/resolv.conf\" | grep nameserver | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" == "$dns_ip" ]

  # verify the pod can query the DNS server
  run sh -c "kubectl exec alpine-sleep -- sh -c \"nslookup nginx.default.svc.cluster.local\""
  [ "$status" -eq 0 ]

  local nslookup=$output
  dns_server=$(echo "$nslookup" | grep "Server" | awk '{print $2}')
  svc_name=$(echo "$nslookup" | grep "Name" | awk '{print $2}')
  svc_ip=$(echo "$nslookup" | grep -A 1 "Name" | grep "Address" | awk '{print $2}')

  [ "$dns_server" == "$dns_ip" ]

  run kubectl exec alpine-sleep -- sh -c "nslookup google.com"
  [ "$status" -eq 0 ]

  # verify DNS resolution works
  run kubectl exec alpine-sleep -- sh -c "apk add curl"
  [ "$status" -eq 0 ]

  run sh -c "kubectl exec alpine-sleep -- sh -c \"curl -s nginx.default.svc.cluster.local\" | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # query the DNS server from the K8s node itself (note that since the
  # node has its own DNS services, we have to point to the cluster's
  # DNS explicitly).

  docker exec $controller sh -c "nslookup nginx.default.svc.cluster.local $dns_ip"
  [ "$status" -eq 0 ]

  # if we repeat the above but without pointing to the cluster's DNS
  # server, it should fail because the node's DNS server's can't see
  # the nginx server (i.e., the nginx service lives inside the
  # cluster)

  docker exec $controller sh -c "nslookup nginx.default.svc.cluster.local"
  [ "$status" -eq 1 ]

  # cleanup

  k8s_del_pod alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kind custom net cluster down" {

  local num_workers=$(cat "$test_dir/.${cluster}_num_workers")
  kindbox_cluster_teardown $cluster $net

  remove_test_dir
}
