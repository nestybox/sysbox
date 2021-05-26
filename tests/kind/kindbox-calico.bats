#!/usr/bin/env bats

# Tests for deploying a K8s cluster inside system container nodes while
# making use of KindBox tool.
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
load ../helpers/fs
load ../helpers/sysbox-health

export test_dir="/tmp/k8s-test/"
export manifest_dir="tests/kind/manifests/"

# Cluster definition.
export cluster=cluster-1
export controller="${cluster}"-master
export num_workers=2
export net=bridge
export cni=calico

# Preset kubeconfig env-var to point to the cluster-config file.
export KUBECONFIG=${HOME}/.kube/${cluster}-config

# Cluster's node image.
export node_image="${CTR_IMG_REPO}/k8s-node-test:v1.18.2"

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

# Testcase #1.
#
#
@test "kindbox cluster up (calico)" {

  k8s_check_sufficient_storage

  create_test_dir

  kindbox_cluster_setup $cluster $num_workers $net $node_image $cni

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/."${cluster}"_num_workers"
}

# Testcase #2.
#
#
@test "kindbox pod (calico)" {

  cat > "$test_dir/basic-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: ${CTR_IMG_REPO}/nginx
EOF

  k8s_create_pod $cluster $controller "$test_dir/basic-pod.yaml"
  retry_run 40 2 "k8s_pod_ready nginx"

  local pod_ip=$(k8s_pod_ip $cluster $controller nginx)

  docker exec $controller sh -c "curl -s $pod_ip | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # cleanup
  k8s_del_pod nginx
  rm "$test_dir/basic-pod.yaml"
}

# Testcase #3.
#
#
@test "kindbox pod multi-container (calico)" {

  cat > "$test_dir/multi-cont-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: multi-cont
spec:
  containers:
  - name: alpine1
    image: ${CTR_IMG_REPO}/alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
  - name: alpine2
    image: ${CTR_IMG_REPO}/alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
EOF

  k8s_create_pod $cluster $controller "$test_dir/multi-cont-pod.yaml"
  retry_run 40 2 "k8s_pod_ready multi-cont"

  # verify all containers in the pod are sharing the net ns

  run kubectl exec multi-cont -c alpine1 readlink /proc/1/ns/net
  [ "$status" -eq 0 ]
  alpine1_ns=$output

  run kubectl exec multi-cont -c alpine2 readlink /proc/1/ns/net
  [ "$status" -eq 0 ]
  alpine2_ns=$output

  [ "$alpine1_ns" == "$alpine2_ns" ]

  # cleanup
  k8s_del_pod multi-cont
  rm "$test_dir/multi-cont-pod.yaml"
}

# Testcase #4.
#
#
@test "kindbox deployment (calico)" {

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.16-alpine
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

# Testcase #5.
#
#
@test "kindbox service clusterIP (calico)" {

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.17-alpine
  [ "$status" -eq 0 ]

  run kubectl scale --replicas=4 deployment nginx
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
  retry_run 10 3 "k8s_pod_ready alpine-sleep"

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

# Testcase #6.
#
#
@test "kindbox service nodePort (calico)" {

  local num_workers=$(cat "$test_dir/."${cluster}"_num_workers")

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.17-alpine
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # create a nodePort service
  run kubectl expose deployment/nginx --port 80 --type NodePort
  [ "$status" -eq 0 ]

  # get the node port for the service
  run sh -c "kubectl get svc nginx -o json | jq .spec.ports[0].nodePort"
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

# Testcase #7.
#
#
@test "kindbox deny all traffic (calico)" {

  cat > "$test_dir/web-deny-all.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-deny-all
spec:
  podSelector:
    matchLabels:
      app: web
  ingress: []
EOF

  # Launch pod + service exposing ingress port.
  run kubectl run web --image=${CTR_IMG_REPO}/nginx --labels app=web \
    --expose --port=80
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready web"

  # Launch web-client to test connection.
  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1"

  run kubectl exec pod/client-1  -- sh -c "wget -qO- --timeout=2 http://web"
  [ "$status" -eq 0 ]

  # Apply a new policy to web deployment.
  kubectl apply -f ${test_dir}/web-deny-all.yaml
  [ "$status" -eq 0 ]

  # Verify creation of network policy.
  run sh -c 'kubectl get networkpolicy --all-namespaces | egrep -q "web-deny-all"'
  [ "$status" -eq 0 ]

  # Launch web-client to test connection.
  run kubectl run client-2 --image=${CTR_IMG_REPO}/alpine -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-2"

  # Verify that traffic is dropped this time.
  run kubectl exec pod/client  -- sh -c "wget -qO- --timeout=2 http://web"
  [ "$status" -eq 1 ]

  #run kubectl logs pod/weave-net-dnx8h -n kube-system weave-npc | egrep "TCP connection from"
  #[ "$status" -eq 0 ]

  # CLean up.
  k8s_del_pod client-2
  k8s_del_pod client-1
  k8s_del_pod web
  run kubectl delete service web
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy web-deny-all
  [ "$status" -eq 0 ]
}

# Testcase #8.
#
#
@test "kindbox limit app traffic (calico)" {

  cat > "$test_dir/api-allow.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: api-allow
spec:
  podSelector:
    matchLabels:
      app: bookstore
      role: api
  ingress:
  - from:
      - podSelector:
          matchLabels:
            app: bookstore
EOF

  # Launch pod + service exposing ingress port.
  run kubectl run apiserver --image=${CTR_IMG_REPO}/nginx \
    --labels app=bookstore,role=api --expose --port=80
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready apiserver"

  run kubectl apply -f ${test_dir}/api-allow.yaml
  [ "$status" -eq 0 ]

  # Verify creation of network policy.
  run sh -c 'kubectl get networkpolicy --all-namespaces | egrep -q "api-allow"'
  [ "$status" -eq 0 ]

  # Create pod with no associated label attached.
  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1"

  # Verify that traffic is rejected.
  run kubectl exec pod/client  -- sh -c "wget -qO- --timeout=2 http://apiserver"
  [ "$status" -eq 1 ]

  # Create pod with label matching the one defined at the policy.
  run kubectl run client-2 --image=${CTR_IMG_REPO}/alpine \
    --labels app=bookstore,role=frontend -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-2"

  # Verify that traffic reaches the web server this time.
  run kubectl exec pod/client-2  -- sh -c "wget -qO- --timeout=2 http://apiserver"
  [ "$status" -eq 0 ]

  # CLean up.
  k8s_del_pod client-2
  k8s_del_pod client-1
  k8s_del_pod apiserver
  run kubectl delete service apiserver
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy api-allow
  [ "$status" -eq 0 ]

  # Identify the node where the api-server node is running and check that traffic
  # is dropped in that particular  weave-net pod.
  # kubectl logs pod/weave-net-x8x8b -n kube-system weave-npc | egrep "TCP connection from"
  #WARN: 2021/05/12 02:47:10.232988 TCP connection from 10.32.0.3:33702 to 10.40.0.1:80 blocked by Weave NPC.
  #WARN: 2021/05/12 02:47:10.233008 TCP connection from 10.32.0.3:33702 to 10.40.0.1:80 blocked by Weave NPC.
  #WARN: 2021/05/12 02:47:11.255958 TCP connection from 10.32.0.3:33702 to 10.40.0.1:80 blocked by Weave NPC.
  #WARN: 2021/05/12 02:47:11.255980 TCP connection from 10.32.0.3:33702 to 10.40.0.1:80 blocked by Weave NPC.
}

# Testcase #9.
#
#
@test "kindbox allow all traffic (calico)" {

  cat > "$test_dir/web-allow-all.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-all
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - {}
EOF

  # Launch pod + service exposing ingress port.
  run kubectl run web --image=${CTR_IMG_REPO}/nginx --labels app=web \
    --expose --port=80
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready web"

  # Apply an allow-all policy to web deployment.
  kubectl apply -f ${test_dir}/web-allow-all.yaml
  [ "$status" -eq 0 ]

  # Verify creation of network policy.
  run sh -c 'kubectl get networkpolicy --all-namespaces | egrep -q "web-allow-all"'
  [ "$status" -eq 0 ]

  # Ensure that enforcing a 'deny-all' policy has no effect -- 'allow-all' prevails.
  kubectl apply -f ${test_dir}/web-deny-all.yaml
  [ "$status" -eq 0 ]

  # Verify creation of network policy.
  run sh -c 'kubectl get networkpolicy --all-namespaces | egrep -q "web-deny-all"'
  [ "$status" -eq 0 ]

  # Launch web-client to test connection.
  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1"

  # Verify that traffic is dropped this time.
  run kubectl exec pod/client-1  -- sh -c "wget -qO- --timeout=2 http://web"
  [ "$status" -eq 0 ]

   # CLean up.
  k8s_del_pod client-1
  k8s_del_pod web
  run kubectl delete service web
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy web-allow-all web-deny-all
  [ "$status" -eq 0 ]
}

# Testcase #10.
#
#
@test "kindbox deny traffic from other namespaces (calico)" {

  cat > "$test_dir/deny-from-other-namespaces.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  namespace: default
  name: deny-from-other-namespaces
spec:
  podSelector:
    matchLabels:
  ingress:
  - from:
    - podSelector: {}
EOF

  # Launch pod + service exposing ingress port.
  run kubectl run web --image=${CTR_IMG_REPO}/nginx --namespace=default \
    --labels app=web --expose --port=80
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready web"

  # Apply a new policy to web deployment.
  kubectl apply -f ${test_dir}/deny-from-other-namespaces.yaml
  [ "$status" -eq 0 ]

  # Launch new pod to verify that traffic coming from 'foo' namespace is blocked
  # when arriving at 'default' one.

  run kubectl create namespace foo
  [ "$status" -eq 0 ]

  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine --namespace=foo \
    -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1 foo"

  run kubectl exec pod/client-1  -- sh -c "wget -qO- --timeout=2 http://web.default"
  [ "$status" -eq 1 ]

  # Try again but this time from a pod in 'default' namespace. Traffic should
  # be forwarded this time around.

  run kubectl run client-2 --image=${CTR_IMG_REPO}/alpine --namespace=default \
    -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-2"

  run kubectl exec pod/client-2  -- sh -c "wget -qO- --timeout=2 http://web.default"
  [ "$status" -eq 0 ]

  # Clean up
  k8s_del_pod client-2
  k8s_del_pod client-1 foo
  k8s_del_pod web
  run kubectl delete service web
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy deny-from-other-namespaces
  [ "$status" -eq 0 ]
  run kubectl delete namespace foo
  [ "$status" -eq 0 ]
}

# Testcase #11.
#
#
@test "kindbox allow traffic from all namespaces (calico)" {

  cat > "$test_dir/web-allow-all-namespaces.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  namespace: default
  name: web-allow-all-namespaces
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - from:
    - namespaceSelector: {}
EOF

  # Launch pod + service exposing ingress port.
  run kubectl run web --image=${CTR_IMG_REPO}/nginx --namespace=default \
    --labels app=web --expose --port=80
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready web"

  # Apply a new policy to web deployment.
  kubectl apply -f ${test_dir}/web-allow-all-namespaces.yaml
  [ "$status" -eq 0 ]

  # Create a new namespace and verify that traffic originated from it is
  # properly forwarded.

  run kubectl create namespace foo
  [ "$status" -eq 0 ]

  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine --namespace=foo \
    -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1 foo"

  run kubectl exec pod/client-1 -n foo -- sh -c "wget -qO- --timeout=2 http://web.default"
  [ "$status" -eq 0 ]

  # Clean up
  k8s_del_pod client-1 foo
  k8s_del_pod web
  run kubectl delete service web
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy web-allow-all-namespaces
  [ "$status" -eq 0 ]
  run kubectl delete namespace foo
  [ "$status" -eq 0 ]
}

# Testcase #12.
#
# Verify that policies that combine multiple clauses and namespaces can be
# properly enforced.
#
@test "kindbox allow traffic from some pods in other namespaces (calico)" {

  # Create policy that combines 'podselector' and 'namespace' selector clauses
  # to restrict traffic to pods with label 'type=monitoring' and that are part
  # of a namespace labeled as 'team=operations'.
  cat > "$test_dir/web-allow-all-ns-monitoring.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-all-ns-monitoring
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
    - from:
      - namespaceSelector:     # chooses all pods in namespaces labelled with team=operations
          matchLabels:
            team: operations
        podSelector:           # chooses pods with type=monitoring
          matchLabels:
            type: monitoring
EOF

  # Launch pod + service exposing ingress port.
  run kubectl run web --image=${CTR_IMG_REPO}/nginx --namespace=default \
    --labels app=web --expose --port=80
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready web"

  # Create foo namespace and label it.
  run kubectl create namespace foo
  [ "$status" -eq 0 ]
  run kubectl label namespace/foo team=operations
  [ "$status" -eq 0 ]

  # Apply a new policy to web deployment.
  kubectl apply -f ${test_dir}/web-allow-all-ns-monitoring.yaml
  [ "$status" -eq 0 ]

  # Verify that traffic originated from default ns and without the proper label is
  # rejected.
  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1"

  run kubectl exec pod/client-1 -- sh -c "wget -qO- --timeout=2 http://web.default"
  [ "$status" -eq 1 ]

  # Verify that traffic originated from foo default ns and with the proper label is
  # rejected.
  run kubectl run client-2 --image=${CTR_IMG_REPO}/alpine -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-2"

  run kubectl exec pod/client-2 -- sh -c "wget -qO- --timeout=2 http://web.default"
  [ "$status" -eq 1 ]

  # Verify that traffic originated from foo ns and without the proper label is
  # rejected.
  run kubectl run client-3 --image=${CTR_IMG_REPO}/alpine --namespace=foo \
    -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-3 foo"

  run kubectl exec pod/client-3 -n foo -- sh -c "wget -qO- --timeout=2 http://web.default"
  [ "$status" -eq 1 ]

  # Finally, verify that traffic originated from foo ns and with the proper label
  # is properly forwarded.
  run kubectl run client-4 --image=${CTR_IMG_REPO}/alpine --namespace=foo \
    --labels type=monitoring -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-4 foo"

  run kubectl exec pod/client-4 -n foo -- sh -c "wget -qO- --timeout=2 http://web.default"
  [ "$status" -eq 0 ]

  # Clean up
  k8s_del_pod client-1
  k8s_del_pod client-2
  k8s_del_pod client-3 foo
  k8s_del_pod client-4 foo
  k8s_del_pod web
  run kubectl delete service web
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy web-allow-all-ns-monitoring
  [ "$status" -eq 0 ]
  run kubectl delete namespace foo
  [ "$status" -eq 0 ]
}

# Testcase #13.
#
# Verify that policies allowing specific (tcp/udp) ports work as expected.
#
@test "kindbox allow traffic to only one port app (calico)" {

  # Policy to allow traffic on port 5000 from pods with label role=monitoring
  # and that are part of the same namespace. All other traffic arriving at the
  # apiserver pod should be rejected.
  cat > "$test_dir/api-allow-5000.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: api-allow-5000
spec:
  podSelector:
    matchLabels:
      app: apiserver
  ingress:
  - ports:
    - port: 5000
    from:
    - podSelector:
        matchLabels:
          role: monitoring
EOF

  # Launch pod hosting two different servers/sockets.
  run kubectl run apiserver --image=ahmet/app-on-two-ports --labels=app=apiserver
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready apiserver"

  # Expose pod's listening sockets (5000 and 8000) through ports 5001 and 8001.
  kubectl create service clusterip apiserver --tcp 8001:8000 --tcp 5001:5000
  [ "$status" -eq 0 ]

  # Apply the new policy.
  kubectl apply -f ${test_dir}/api-allow-5000.yaml
  [ "$status" -eq 0 ]

  # Verify that traffic originated from untagged pods is blocked, regardless of
  # the destination port.
  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1"

  run kubectl exec pod/client-1 -- sh -c "wget -qO- --timeout=2 http://apiserver:8001"
  [ "$status" -eq 1 ]
  run kubectl exec pod/client-1 -- sh -c "wget -qO- --timeout=2 http://apiserver:5001/metrics"
  [ "$status" -eq 1 ]

  # Verify that traffic originated from a properly tagged pod is forwarded to port
  # 5000 but continues to be blocked for port 8000.
  run kubectl run client-2 --image=${CTR_IMG_REPO}/alpine --labels=role=monitoring \
    -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-2"

  run kubectl exec pod/client-2 -- sh -c "wget -qO- --timeout=2 http://apiserver:8001"
  [ "$status" -eq 1 ]
  run kubectl exec pod/client-2 -- sh -c "wget -qO- --timeout=2 http://apiserver:5001/metrics"
  [ "$status" -eq 0 ]

  # Clean up
  k8s_del_pod client-1
  k8s_del_pod client-2
  k8s_del_pod apiserver
  run kubectl delete service apiserver
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy api-allow-5000
  [ "$status" -eq 0 ]
}

# Testcase #14.
#
# Verify that network policies with multiple selectors can be enforced.
#
@test "kindbox allow traffic using multiple selectors (calico)" {

  # Policy to allow traffic originated at pods belonging to specific
  # microservices. All other traffic must be rejected.
  cat > "$test_dir/web-allow-services.yaml" <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-services
spec:
  podSelector:
    matchLabels:
      app: bookstore
      role: web
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: bookstore
          role: search
    - podSelector:
        matchLabels:
          app: bookstore
          role: api
    - podSelector:
        matchLabels:
          app: inventory
          role: web
EOF

  # Launch pod + service exposing ingress port.
  run kubectl run web --image=${CTR_IMG_REPO}/nginx --namespace=default \
    --labels app=bookstore,role=web --expose --port=80
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready web"

  # Apply the new policy.
  kubectl apply -f ${test_dir}/web-allow-services.yaml
  [ "$status" -eq 0 ]

  # Verify that traffic originated from allowed microservices is properly
  # forwarded.
  run kubectl run client-1 --image=${CTR_IMG_REPO}/alpine \
    --labels=app=inventory,role=web -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-1"

  run kubectl exec pod/client-1 -- sh -c "wget -qO- --timeout=2 http://web"
  [ "$status" -eq 0 ]

  # Verify that traffic originated from pods with unknown labels is rejected.
  run kubectl run client-2 --image=${CTR_IMG_REPO}/alpine --labels=app=other \
    -- sleep infinity
  [ "$status" -eq 0 ]

  retry_run 10 3 "k8s_pod_ready client-2"

  run kubectl exec pod/client-2 -- sh -c "wget -qO- --timeout=2 http://web"
  [ "$status" -eq 1 ]

  # Clean up
  k8s_del_pod client-1
  k8s_del_pod client-2
  k8s_del_pod web
  run kubectl delete service web
  [ "$status" -eq 0 ]
  run kubectl delete networkpolicy web-allow-services
  [ "$status" -eq 0 ]
}

@test "kindbox cluster down" {

  kindbox_cluster_teardown $cluster $net
  remove_test_dir
}
