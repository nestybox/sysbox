#!/usr/bin/env bats

# Tests for deploying a K8s cluster inside system container nodes.
#
# The system container nodes have K8s + Docker inside (i.e., K8s uses Docker to
# deploy pods).
#
# NOTE: the "cluster up" test must execute before all others,
# as it brings up the K8s cluster. Similarly, the "cluster down"
# test must execute after all other tests.

load ../helpers/run
load ../helpers/docker
load ../helpers/k8s
load ../helpers/fs
load ../helpers/sysbox-health

export k8s_version=v1.18.2
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

@test "kind (inner docker) cluster up" {

  k8s_check_sufficient_storage

  create_test_dir

  run __docker network rm k8s-net

  docker network create k8s-net
  [ "$status" -eq 0 ]

  local cluster_name=k8s
  local num_workers=2
  local net=k8s-net
  local node_image=nestybox/k8s-node-with-docker-test

  k8s_cluster_setup $cluster_name $num_workers $net $node_image $k8s_version

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/.k8s_num_workers"
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

  docker exec k8s-master sh -c "kubectl scale --replicas=4 deployment nginx"
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

  docker exec k8s-master sh -c "kubectl scale --replicas=8 deployment nginx"
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
  local node_ip=$(k8s_node_ip k8s-worker-1)
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

  # "cp + rm" because "mv" fails with "resource busy" as /etc/hosts is
  # a bind-mount inside the container
  cp /etc/hosts.orig /etc/hosts
  rm /etc/hosts.orig
}

@test "vol: hostPath" {

  # create a directory and a file on the k8s-node; each will be
  # mounted as a hostPath vol into a pod
  docker exec k8s-worker-0 sh -c "mkdir -p /root/hpdir && echo hi > /root/hpdir/test"
  [ "$status" -eq 0 ]
  docker exec k8s-worker-0 sh -c "echo hello > /root/hpfile"
  [ "$status" -eq 0 ]

  # create a test pod with the hostPath vol; must be scheduled on
  # k8s-worker-0 since that's where the host volume is at.
cat > "$test_dir/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: hp-test
spec:
  nodeSelector:
    kubernetes.io/hostname: k8s-worker-0
  containers:
  - image: alpine
    name: alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
    volumeMounts:
    - mountPath: /hostdir
      name: hp-dir-vol
    - mountPath: /hostfile
      name: hp-file-vol
  volumes:
  - name: hp-dir-vol
    hostPath:
      path: /root/hpdir
      type: Directory
  - name: hp-file-vol
    hostPath:
      path: /root/hpfile
      type: File
EOF

  k8s_create_pod k8s-master "$test_dir/pod.yaml"
  retry_run 40 2 "k8s_pod_ready k8s-master hp-test"

  # verify the pod sees the host volumes
  docker exec k8s-master sh -c "kubectl exec hp-test -- cat /hostdir/test"
  [ "$status" -eq 0 ]
  [ "$output" == "hi" ]

  docker exec k8s-master sh -c "kubectl exec hp-test -- cat /hostfile"
  [ "$status" -eq 0 ]
  [ "$output" == "hello" ]

  # write to the volume from the pod, verify the host sees the changes

  docker exec k8s-master sh -c "kubectl exec hp-test -- sh -c \"echo pod > /hostdir/pod-file\""
  [ "$status" -eq 0 ]
  docker exec k8s-master sh -c "kubectl exec hp-test -- sh -c \"echo pod > /hostfile\""
  [ "$status" -eq 0 ]

  docker exec k8s-worker-0 sh -c "cat /root/hpdir/pod-file"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  docker exec k8s-worker-0 sh -c "cat /root/hpfile"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  # verify volume permissions inside pod look good
  docker exec k8s-master sh -c "kubectl exec hp-test -- sh -c \"ls -l / | grep hostdir\""
  [ "$status" -eq 0 ]
  verify_perm_owner "drwxr-xr-x" "root" "root" "$output"

  docker exec k8s-master sh -c "kubectl exec hp-test -- sh -c \"ls -l / | grep hostfile\""
  [ "$status" -eq 0 ]
  verify_perm_owner "-rw-r--r--" "root" "root" "$output"

  #cleanup
  k8s_del_pod k8s-master hp-test

  docker exec k8s-worker-0 sh -c "rm -rf /root/hpdir && rm /root/hpfile"
  [ "$status" -eq 0 ]

  rm "$test_dir/pod.yaml"
}

# Verifies Helm v3 proper operation.
@test "helm v3 basic" {

  # Install Helm V3.
  helm_v3_install k8s-master

  # Install new Helm chart for the nginx ingress controller; must set
  # its type to NodePort since we are not using a cloud load balancer
  # (or equivalent).
  docker exec k8s-master sh -c "helm install nginx-ingress stable/nginx-ingress --set rbac.create=true --set controller.service.type=NodePort"
  [ "$status" -eq 0 ]

  sleep 1

  # Install an nginx ingress controller using a Helm chart
  docker exec k8s-master sh -c "helm ls | grep -q \"nginx-ingress\""
  [ "$status" -eq 0 ]

  docker exec k8s-master sh -c "kubectl get pods -o wide"
  [ "$status" -eq 0 ]

  local pod1_name=$(echo ${lines[1]} | awk '{print $1}')
  local pod2_name=$(echo ${lines[2]} | awk '{print $1}')

  # Wait till the new pods are fully up and running.
  retry_run 40 3 "k8s_pod_ready k8s-master $pod1_name"
  retry_run 40 3 "k8s_pod_ready k8s-master $pod2_name"

  # Verify that the ingress controller works
  verify_nginx_ingress k8s-master nginx-ingress-controller

  # Cleanup
  docker exec k8s-master sh -c "helm delete nginx-ingress"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_cluster_is_clean k8s-master"

  # Verify the Helm chart is properly eliminated.
  docker exec k8s-master sh -c "helm ls | grep -q \"nginx-ingress\""
  [ "$status" -eq 1 ]

  # Uninstall Helm v3
  helm_v3_uninstall k8s-master
}

@test "kind (inner docker) cluster down" {

  local num_workers=$(cat "$test_dir/.k8s_num_workers")
  k8s_cluster_teardown k8s $num_workers

  # wait for cluster teardown to complete
  sleep 10

  docker network rm k8s-net
  [ "$status" -eq 0 ]

  remove_test_dir
}
