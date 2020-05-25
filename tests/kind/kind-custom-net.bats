#!/usr/bin/env bats

# Test k8s clusters on top of a Docker custom bridge network
#
# NOTE: the "kind custom net cluster up" test must execute before all others,
# as it brings up the K8s cluster. Similarly, the "kind cluster down"
# test must execute after all other tests.

load ../helpers/run
load ../helpers/docker
load ../helpers/k8s
load ../helpers/sysbox-health

export test_dir="/tmp/k8s-test/"
export manifest_dir="tests/kind/manifests/"

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

  run __docker network rm k8s-net

  docker network create k8s-net
  [ "$status" -eq 0 ]

  local num_workers=2
  local kubeadm_join=$(k8s_cluster_setup k8s $num_workers k8s-net)

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/.k8s_num_workers"
  echo $kubeadm_join > "$test_dir/.kubeadm_join"
}

@test "kind deployment" {

  docker exec k8s-master sh -c "kubectl create deployment nginx --image=nginx:1.16-alpine"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready k8s-master default nginx"

  # scale up
  docker exec k8s-master sh -c "kubectl scale --replicas=4 deployment nginx"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready k8s-master default nginx"

  # rollout new nginx image
  docker exec k8s-master sh -c "kubectl set image deployment/nginx nginx=nginx:1.17-alpine --record"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_rollout_ready k8s-master default nginx"

  # scale down
  docker exec k8s-master sh -c "kubectl scale --replicas=1 deployment nginx"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready k8s-master default nginx"

  # cleanup
  docker exec k8s-master sh -c "kubectl delete deployments.apps nginx"
  [ "$status" -eq 0 ]
}

@test "kind service clusterIP" {

  docker exec k8s-master sh -c "kubectl create deployment nginx --image=nginx:1.17-alpine"
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl scale --replicas=3 deployment nginx"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready k8s-master default nginx"

  # create a service and confirm it's there
  docker exec k8s-master sh -c "kubectl expose deployment/nginx --port 80"
  [ "$status" -eq 0 ]

  local svc_ip=$(k8s_svc_ip k8s-master default nginx)

  docker exec k8s-master sh -c "curl -s $svc_ip | grep -q \"Welcome to nginx\""
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

  k8s_create_pod k8s-master /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready k8s-master alpine-sleep"

  docker exec k8s-master sh -c "kubectl exec alpine-sleep -- sh -c \"apk add curl\""
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c 'kubectl exec alpine-sleep -- sh -c "curl -s \$NGINX_SERVICE_HOST" | grep -q "Welcome to nginx"'
  [ "$status" -eq 0 ]

  # verify the kube-proxy is using iptables (does so by default)
  k8s_check_proxy_mode k8s-master iptables

  # verify k8s has programmed iptables inside the sys container net ns
  docker exec k8s-master sh -c "iptables -L | grep -q KUBE"
  [ "$status" -eq 0 ]

  # verify no k8s iptable chains are seen outside the sys container net ns
  iptables -L | grep -qv KUBE

  # cleanup
  k8s_del_pod k8s-master alpine-sleep

  docker exec k8s-master sh -c "kubectl delete svc nginx"
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl delete deployments.apps nginx"
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kind service nodePort" {

  local num_workers=$(cat "$test_dir/.k8s_num_workers")

  docker exec k8s-master sh -c "kubectl create deployment nginx --image=nginx:1.17-alpine"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready k8s-master default nginx"

  # create a nodePort service
  docker exec k8s-master sh -c "kubectl expose deployment/nginx --port 80 --type NodePort"
  [ "$status" -eq 0 ]

  # get the node port for the service
  docker exec k8s-master sh -c "kubectl get svc nginx -o json | jq .spec.ports[0].nodePort"
  [ "$status" -eq 0 ]
  svc_port=$output

  # verify the service is exposed on all nodes of the cluster
  node_ip=$(k8s_node_ip k8s-master)
  curl -s $node_ip:$svc_port | grep "Welcome to nginx"

  for i in `seq 0 $(( $num_workers - 1 ))`; do
    local worker=k8s-worker-$i
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

  k8s_create_pod k8s-master /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready k8s-master alpine-sleep"

  docker exec k8s-master sh -c "kubectl exec alpine-sleep -- sh -c \"apk add curl\""
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c 'kubectl exec alpine-sleep -- sh -c "curl -s \$NGINX_SERVICE_HOST" | grep -q "Welcome to nginx"'
  [ "$status" -eq 0 ]

  # cleanup
  k8s_del_pod k8s-master alpine-sleep

  docker exec k8s-master sh -c "kubectl delete svc nginx"
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl delete deployments.apps nginx"
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kind DNS clusterIP" {

  # launch a deployment with an associated service

  docker exec k8s-master sh -c "kubectl create deployment nginx --image=nginx:1.17-alpine"
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl expose deployment/nginx --port 80"
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

  k8s_create_pod k8s-master /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready k8s-master alpine-sleep"

  # find the cluster's DNS IP address
  docker exec k8s-master sh -c "kubectl get services --all-namespaces -o wide | grep kube-dns | awk '{print \$4}'"
  [ "$status" -eq 0 ]
  local dns_ip=$output

  # verify the pod has the cluster DNS server in its /etc/resolv.conf
  docker exec k8s-master sh -c "kubectl exec alpine-sleep -- sh -c \"cat /etc/resolv.conf\" | grep nameserver | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" == "$dns_ip" ]

  # verify the pod can query the DNS server
  docker exec k8s-master sh -c "kubectl exec alpine-sleep -- sh -c \"nslookup nginx.default.svc.cluster.local\""
  [ "$status" -eq 0 ]

  local nslookup=$output
  dns_server=$(echo "$nslookup" | grep "Server" | awk '{print $2}')
  svc_name=$(echo "$nslookup" | grep "Name" | awk '{print $2}')
  svc_ip=$(echo "$nslookup" | grep -A 1 "Name" | grep "Address" | awk '{print $2}')

  [ "$dns_server" == "$dns_ip" ]

  docker exec k8s-master sh -c "kubectl exec alpine-sleep -- sh -c \"nslookup google.com\""
  [ "$status" -eq 0 ]

  # verify DNS resolution works
  docker exec k8s-master sh -c "kubectl exec alpine-sleep -- sh -c \"apk add curl\""
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl exec alpine-sleep -- sh -c \"curl -s nginx.default.svc.cluster.local\" | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # query the DNS server from the K8s node itself (note that since the
  # node has its own DNS services, we have to point to the cluster's
  # DNS explicitly).

  docker exec k8s-master sh -c "nslookup nginx.default.svc.cluster.local $dns_ip"
  [ "$status" -eq 0 ]

  # if we repeat the above but without pointing to the cluster's DNS
  # server, it should fail because the node's DNS server's can't see
  # the nginx server (i.e., the nginx service lives inside the
  # cluster)

  docker exec k8s-master sh -c "nslookup nginx.default.svc.cluster.local"
  [ "$status" -eq 1 ]

  # cleanup

  k8s_del_pod k8s-master alpine-sleep

  docker exec k8s-master sh -c "kubectl delete svc nginx"
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl delete deployments.apps nginx"
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kind ingress" {

  # Based on:
  # https://docs.traefik.io/v1.7/user-guide/kubernetes/

  # the test will be modifying /etc/hosts in the test container;
  # create a backup so we can revert it after the test finishes.
  cp /etc/hosts /etc/hosts.orig

  # deploy the ingress controller (traefik) and associated services and ingress rules
  k8s_apply k8s-master $manifest_dir/traefik.yaml

  retry_run 40 2 "k8s_daemonset_ready k8s-master kube-system traefik-ingress-controller"

  # setup the ingress hostname in /etc/hosts
  local node_ip=$(k8s_node_ip k8s-worker-0)
  echo "$node_ip traefik-ui.nestykube" >> /etc/hosts

  # verify ingress to traefik-ui works
  sleep 20

  wget traefik-ui.nestykube -O $test_dir/index.html
  grep Traefik $test_dir/index.html
  rm $test_dir/index.html

  # deploy nginx and create a service for it
  docker exec k8s-master sh -c "kubectl create deployment nginx --image=nginx:1.16-alpine"
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl scale --replicas=3 deployment nginx"
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl expose deployment/nginx --port 80"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready k8s-master default nginx"

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
  k8s_apply k8s-master $test_dir/nginx-ing.yaml

  retry_run 40 2 "k8s_daemonset_ready k8s-master kube-system traefik-ingress-controller"

  # setup the ingress hostname in /etc/hosts
  local node_ip=$(k8s_node_ip k8s-worker-0)
  echo "$node_ip nginx.nestykube" >> /etc/hosts

  # verify ingress to nginx works
  sleep 3

  wget nginx.nestykube -O $test_dir/index.html
  grep "Welcome to nginx" $test_dir/index.html
  rm $test_dir/index.html

  # cleanup
  docker exec k8s-master sh -c "kubectl delete ing nginx"
  [ "$status" -eq 0 ]
  docker exec k8s-master sh -c "kubectl delete svc nginx"
  [ "$status" -eq 0 ]
  docker exec k8s-master sh -c "kubectl delete deployment nginx"
  [ "$status" -eq 0 ]

  k8s_delete k8s-master $manifest_dir/traefik.yaml

  rm $test_dir/nginx-ing.yaml
  cp /etc/hosts.orig /etc/hosts
}

@test "kind custom net cluster2 up" {

  run __docker network rm k8s-net2

  docker network create k8s-net2
  [ "$status" -eq 0 ]

  local num_workers=1

  k8s_cluster_setup cluster2 $num_workers k8s-net2

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/.cluster2_num_workers"

  # launch a k8s deployment
  docker exec cluster2-master sh -c "kubectl create deployment nginx --image=nginx:1.17-alpine"
  [ "$status" -eq 0 ]

  docker exec cluster2-master sh -c "kubectl scale --replicas=4 deployment nginx"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready cluster2-master default nginx"

  # create a service and confirm it's there
  docker exec cluster2-master sh -c "kubectl expose deployment/nginx --port 80"
  [ "$status" -eq 0 ]

  local svc_ip=$(k8s_svc_ip cluster2-master default nginx)

  docker exec cluster2-master sh -c "curl -s $svc_ip | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # verify the two k8s clusters are isolated

  ## nodes
  docker exec k8s-master sh -c "kubectl get nodes cluster2-master"
  [ "$status" -eq 1 ]

  docker exec k8s-master sh -c "kubectl get nodes cluster2-worker-0"
  [ "$status" -eq 1 ]

  docker exec cluster2-master sh -c "kubectl get nodes k8s-master"
  [ "$status" -eq 1 ]

  docker exec cluster2-master sh -c "kubectl get nodes k8s-worker-0"
  [ "$status" -eq 1 ]

  ## deployments
  docker exec k8s-master sh -c "kubectl get deployment nginx"
  [ "$status" -eq 1 ]

  ## services
  docker exec k8s-master sh -c "kubectl get svc nginx"
  [ "$status" -eq 1 ]

  # cleanup
  docker exec cluster2-master sh -c "kubectl delete svc nginx"
  [ "$status" -eq 0 ]

  docker exec cluster2-master sh -c "kubectl delete deployments.apps nginx"
  [ "$status" -eq 0 ]
}

# Install Istio and verify the proper operation of its main components through
# the instantiation of a basic service-mesh. More details here:
# https://istio.io/docs/setup/getting-started/
@test "kind istio basic" {

  # Install Istio in original cluster.
  istio_install k8s-master

  # Deploy Istio sample app.
  docker exec k8s-master sh -c "kubectl apply -f istio*/samples/bookinfo/platform/kube/bookinfo.yaml"
  [ "$status" -eq 0 ]

  # Obtain list / names of pods launched as part of this app.
  docker exec k8s-master sh -c "kubectl get pods -o wide"
  [ "$status" -eq 0 ]

  pod_names[0]=$(echo ${lines[1]} | awk '{print $1}')
  pod_names[1]=$(echo ${lines[2]} | awk '{print $1}')
  pod_names[2]=$(echo ${lines[3]} | awk '{print $1}')
  pod_names[3]=$(echo ${lines[4]} | awk '{print $1}')
  pod_names[4]=$(echo ${lines[5]} | awk '{print $1}')
  pod_names[5]=$(echo ${lines[6]} | awk '{print $1}')

  # Wait for all the app pods to be ready (istio sidecars will be intantiated too).
  retry_run 60 5 "k8s_pod_array_ready k8s-master ${pod_names[@]}"

  # Obtain app pods again (after waiting instruction) to dump their state if an
  # error is eventually encountered.
  docker exec k8s-master sh -c "kubectl get pods -o wide"
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  # Check if app is running and serving HTML pages.
  docker exec k8s-master sh -c "kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}'"
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  docker exec -d k8s-master sh -c "kubectl exec $output -c ratings -- curl -s productpage:9080/productpage | grep -q \"<title>.*</title>\""
  echo "status = ${status}"
  echo "output = ${output}"
  [ "$status" -eq 0 ]

  # Uninstall Istio in original cluster.
  istio_uninstall k8s-master

  retry_run 40 2 "k8s_cluster_is_clean k8s-master"
}

@test "kind custom net cluster down" {

  local num_workers=$(cat "$test_dir/.k8s_num_workers")
  k8s_cluster_teardown k8s $num_workers

  num_workers=$(cat "$test_dir/.cluster2_num_workers")
  k8s_cluster_teardown cluster2 $num_workers

  # wait for cluster teardown to complete
  sleep 10

  docker network rm k8s-net
  [ "$status" -eq 0 ]

  docker network rm k8s-net2
  [ "$status" -eq 0 ]

  remove_test_dir
}
