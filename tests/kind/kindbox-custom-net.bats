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

# Cluster1 definition.
export cluster1=cluster1
export controller1="${cluster1}"-master
export net1="${cluster1}"-net
export num_workers1=2

# Cluster2 definition.
export cluster2=cluster2
export controller2="${cluster2}"-master
export net2="${cluster2}"-net
export num_workers2=1

# Preset kubeconfig env-var to point to both cluster-configs.
export KUBECONFIG=${HOME}/.kube/${cluster1}-config:${HOME}/.kube/${cluster2}-config

# Cluster's node image.
export node_image="nestybox/k8s-node-test:v1.18.2"


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

@test "kindbox custom net cluster up" {

  k8s_check_sufficient_storage

  create_test_dir

  # Create new cluster.
  kindbox_cluster_setup $cluster1 $num_workers1 $net1 $node_image

  # Switch to the cluster context just created.
  kubectl config use-context kubernetes-admin@"${cluster1}"
  [ "$status" -eq 0 ]

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/."${cluster1}"_num_workers"
}

@test "kindbox deployment" {

  run kubectl create deployment nginx --image=nginx:1.16-alpine
  echo "status = ${status}"
  echo "output = ${output}"
  echo "kubeconfig = $(echo $KUBECONFIG)"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster1 $controller1 default nginx"

  # scale up
  run kubectl scale --replicas=4 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster1 $controller1 default nginx"

  # rollout new nginx image
  run kubectl set image deployment/nginx nginx=nginx:1.17-alpine --record
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_rollout_ready $cluster1 $controller1 default nginx"

  # scale down
  run kubectl scale --replicas=1 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster1 $controller1 default nginx"

  # cleanup
  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]
}

@test "kindbox service clusterIP" {

  run kubectl create deployment nginx --image=nginx:1.17-alpine
  [ "$status" -eq 0 ]

  run kubectl scale --replicas=3 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster1 $controller1 default nginx"

  # create a service and confirm it's there
  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  local svc_ip=$(k8s_svc_ip $cluster1 $controller1 default nginx)

  docker exec $controller1 sh -c "curl -s $svc_ip | grep -q \"Welcome to nginx\""
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
    image: alpine
    args:
    - sleep
    - "1000000"
EOF

  k8s_create_pod $cluster1 $controller1 /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready $cluster1 $controller1 alpine-sleep"

  run kubectl exec alpine-sleep -- sh -c "apk add curl"
  [ "$status" -eq 0 ]

  run sh -c 'kubectl exec alpine-sleep -- sh -c "curl -s \$NGINX_SERVICE_HOST" | grep -q "Welcome to nginx"'
  [ "$status" -eq 0 ]

  # verify the kube-proxy is using iptables (does so by default)
  k8s_check_proxy_mode $cluster1 $controller1 iptables

  # verify k8s has programmed iptables inside the sys container net ns
  docker exec $controller1 sh -c "iptables -L | grep -q KUBE"
  [ "$status" -eq 0 ]

  # verify no k8s iptable chains are seen outside the sys container net ns
  iptables -L | grep -qv KUBE

  # cleanup
  k8s_del_pod $cluster1 $controller1 alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kindbox service nodePort" {

  local num_workers=$(cat "$test_dir/."${cluster1}"_num_workers")

  run kubectl create deployment nginx --image=nginx:1.17-alpine
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster1 $controller1 default nginx"

  # create a nodePort service
  run kubectl expose deployment/nginx --port 80 --type NodePort
  [ "$status" -eq 0 ]

  # get the node port for the service
  run sh -c 'kubectl get svc nginx -o json | jq .spec.ports[0].nodePort'
  [ "$status" -eq 0 ]
  svc_port=$output

  # verify the service is exposed on all nodes of the cluster
  node_ip=$(k8s_node_ip $controller1)
  curl -s $node_ip:$svc_port | grep "Welcome to nginx"

  for i in `seq 0 $(( $num_workers - 1 ))`; do
    local worker=${cluster}-worker-$i
    node_ip=$(k8s_node_ip $worker)
    curl -s $node_ip:$svc_port | grep -q "Welcome to nginx"
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
    image: alpine
    args:
    - sleep
    - "1000000"
EOF

  k8s_create_pod $cluster1 $controller1 /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready $cluster1 $controller1 alpine-sleep"

  run kubectl exec alpine-sleep -- sh -c "apk add curl"
  [ "$status" -eq 0 ]

  run sh -c 'kubectl exec alpine-sleep -- sh -c "curl -s \$NGINX_SERVICE_HOST" | grep -q "Welcome to nginx"'
  [ "$status" -eq 0 ]

  # cleanup
  k8s_del_pod $cluster1 $controller1 alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kindbox DNS clusterIP" {

  # launch a deployment with an associated service

  run kubectl create deployment nginx --image=nginx:1.17-alpine
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
    image: alpine
    args:
    - sleep
    - "1000000"
EOF

  k8s_create_pod $cluster1 $controller1 /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready $cluster1 $controller1 alpine-sleep"

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

  docker exec $controller1 sh -c "nslookup nginx.default.svc.cluster.local $dns_ip"
  [ "$status" -eq 0 ]

  # if we repeat the above but without pointing to the cluster's DNS
  # server, it should fail because the node's DNS server's can't see
  # the nginx server (i.e., the nginx service lives inside the
  # cluster)

  docker exec $controller1 sh -c "nslookup nginx.default.svc.cluster.local"
  [ "$status" -eq 1 ]

  # cleanup

  k8s_del_pod $cluster1 $controller1 alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kindbox ingress" {

  # Based on:
  # https://docs.traefik.io/v1.7/user-guide/kubernetes/

  # the test will be modifying /etc/hosts in the test container;
  # create a backup so we can revert it after the test finishes.
  cp /etc/hosts /etc/hosts.orig

  # deploy the ingress controller (traefik) and associated services and ingress rules
  k8s_apply $cluster1 $controller1 $manifest_dir/traefik.yaml

  retry_run 40 2 "k8s_daemonset_ready $cluster1 $controller1 kube-system traefik-ingress-controller"

  # setup the ingress hostname in /etc/hosts
  local node_ip=$(k8s_node_ip "${cluster1}"-worker-0)
  echo "$node_ip traefik-ui.nestykube" >> /etc/hosts

  # verify ingress to traefik-ui works
  sleep 20

  wget traefik-ui.nestykube -O $test_dir/index.html
  grep Traefik $test_dir/index.html
  rm $test_dir/index.html

  # deploy nginx and create a service for it
  run kubectl create deployment nginx --image=nginx:1.16-alpine
  [ "$status" -eq 0 ]

  run kubectl scale --replicas=3 deployment nginx
  [ "$status" -eq 0 ]

  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster1 $controller1 default nginx"

  # create an ingress rule for the nginx service
cat > "$test_dir/nginx-ing.yaml" <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx
  annotations:
    kubernetes.io/ingress.class: traefik
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
  k8s_apply $cluster1 $controller1 $test_dir/nginx-ing.yaml

  retry_run 40 2 "k8s_daemonset_ready $cluster1 $controller1 kube-system traefik-ingress-controller"

  # setup the ingress hostname in /etc/hosts
  local node_ip=$(k8s_node_ip "${cluster1}"-worker-1)
  echo "$node_ip nginx.nestykube" >> /etc/hosts

  # verify ingress to nginx works
  sleep 3

  wget nginx.nestykube -O $test_dir/index.html
  grep "Welcome to nginx" $test_dir/index.html
  rm $test_dir/index.html

  # cleanup
  run kubectl delete ing nginx
  [ "$status" -eq 0 ]
  run kubectl delete svc nginx
  [ "$status" -eq 0 ]
  run kubectl delete deployment nginx
  [ "$status" -eq 0 ]

  k8s_delete $cluster1 $controller1 $manifest_dir/traefik.yaml

  rm $test_dir/nginx-ing.yaml
  cp /etc/hosts.orig /etc/hosts
}

@test "kindbox custom net cluster2 up" {

  kindbox_cluster_setup $cluster2 $num_workers2 $net2 $node_image

  run kubectl config use-context kubernetes-admin@"${cluster2}"
  [ "$status" -eq 0 ]

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/."${cluster2}"_num_workers"

  # launch a k8s deployment
  run kubectl create deployment nginx --image=nginx:1.17-alpine
  [ "$status" -eq 0 ]

  run kubectl scale --replicas=4 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster2 $controller2 default nginx"

  # create a service and confirm it's there
  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  local svc_ip=$(k8s_svc_ip $cluster2 $controller2 default nginx)

  docker exec $controller2 sh -c "curl -s $svc_ip | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # Verify the two k8s clusters are isolated.

  ## Check nodes.
  run kubectl config use-context kubernetes-admin@"${cluster1}"
  [ "$status" -eq 0 ]

  run kubectl get nodes $controller2
  [ "$status" -eq 1 ]

  run kubectl get nodes ${cluster2}-worker-0
  [ "$status" -eq 1 ]

  ## Switch to cluster2 context.
  run kubectl config use-context kubernetes-admin@"${cluster2}"
  [ "$status" -eq 0 ]

  run kubectl get nodes $controller1
  [ "$status" -eq 1 ]

  run kubectl get nodes ${cluster1}-worker-0
  [ "$status" -eq 1 ]

  ## Check deployments.

  ## Switch to cluster1 context.
  run kubectl config use-context kubernetes-admin@"${cluster1}"
  [ "$status" -eq 0 ]

  run kubectl get deployment nginx
  [ "$status" -eq 1 ]

  ## Check services.
  run kubectl get svc nginx
  [ "$status" -eq 1 ]

  # Cleanup.

  ## Switch to cluster2 context.
  run kubectl config use-context kubernetes-admin@"${cluster2}"
  [ "$status" -eq 0 ]

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  # Switch to cluster1 context before exiting.
  run kubectl config use-context kubernetes-admin@"${cluster1}"
  [ "$status" -eq 0 ]
}

# Install Istio and verify the proper operation of its main components through
# the instantiation of a basic service-mesh. More details here:
# https://istio.io/docs/setup/getting-started/
@test "kindbox istio basic" {

  # Install Istio in original cluster.
  istio_install $cluster1 $controller1

  # Deploy Istio sample app.
  docker exec $controller1 sh -c "kubectl apply -f istio*/samples/bookinfo/platform/kube/bookinfo.yaml"
  [ "$status" -eq 0 ]

  # Obtain list / names of pods launched as part of this app.
  run kubectl get pods -o wide
  [ "$status" -eq 0 ]

  pod_names[0]=$(echo ${lines[1]} | awk '{print $1}')
  pod_names[1]=$(echo ${lines[2]} | awk '{print $1}')
  pod_names[2]=$(echo ${lines[3]} | awk '{print $1}')
  pod_names[3]=$(echo ${lines[4]} | awk '{print $1}')
  pod_names[4]=$(echo ${lines[5]} | awk '{print $1}')
  pod_names[5]=$(echo ${lines[6]} | awk '{print $1}')

  # Wait for all the app pods to be ready (istio sidecars will be intantiated too).
  retry_run 60 5 "k8s_pod_array_ready $cluster1 $controller1 ${pod_names[@]}"

  # Obtain app pods again (after waiting instruction) to dump their state if an
  # error is eventually encountered.
  run kubectl get pods -o wide
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  # Check if app is running and serving HTML pages.
  run kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}'
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  run sh -c "kubectl exec $output -c ratings -- curl -s productpage:9080/productpage | grep -q \"<title>.*</title>\""
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  # Uninstall Istio in original cluster.
  istio_uninstall $cluster1 $controller1

  retry_run 40 2 "k8s_cluster_is_clean $cluster1 $controller1"
}

@test "kindbox custom net cluster down" {

  local num_workers=$(cat "$test_dir/."${cluster1}"_num_workers")
  kindbox_cluster_teardown $cluster1

  # Switch to cluster2 context.
  run kubectl config use-context kubernetes-admin@"${cluster2}"
  [ "$status" -eq 0 ]

  num_workers=$(cat "$test_dir/."${cluster2}"_num_workers")
  kindbox_cluster_teardown $cluster2

  remove_test_dir
}
