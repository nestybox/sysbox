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
export cluster=cluster1
export controller="${cluster}"-master
export num_workers=2
export net=bridge

# Preset kubeconfig env-var to point to the cluster-config file.
export KUBECONFIG=${HOME}/.kube/${cluster}-config

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

@test "kindbox cluster up" {

  k8s_check_sufficient_storage

  create_test_dir

  kindbox_cluster_setup $cluster $num_workers $net $node_image

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/."${cluster}"_num_workers"
}

@test "kindbox pod" {

  cat > "$test_dir/basic-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx
EOF

  k8s_create_pod $cluster $controller "$test_dir/basic-pod.yaml"
  retry_run 40 2 "k8s_pod_ready $cluster $controller nginx"

  local pod_ip=$(k8s_pod_ip $cluster $controller nginx)

  docker exec $controller sh -c "curl -s $pod_ip | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # cleanup
  k8s_del_pod $cluster $controller nginx
  rm "$test_dir/basic-pod.yaml"
}

@test "kindbox pod multi-container" {

  cat > "$test_dir/multi-cont-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: multi-cont
spec:
  containers:
  - name: alpine1
    image: alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
  - name: alpine2
    image: alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
EOF

  k8s_create_pod $cluster $controller "$test_dir/multi-cont-pod.yaml"
  retry_run 40 2 "k8s_pod_ready $cluster $controller multi-cont"

  # verify all containers in the pod are sharing the net ns

  run kubectl exec multi-cont -c alpine1 readlink /proc/1/ns/net
  [ "$status" -eq 0 ]
  alpine1_ns=$output

  run kubectl exec multi-cont -c alpine2 readlink /proc/1/ns/net
  [ "$status" -eq 0 ]
  alpine2_ns=$output

  [ "$alpine1_ns" == "$alpine2_ns" ]

  # cleanup
  k8s_del_pod $cluster $controller multi-cont
  rm "$test_dir/multi-cont-pod.yaml"
}

@test "kindbox deployment" {

  run kubectl create deployment nginx --image=nginx:1.16-alpine
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # scale up
  run kubectl scale --replicas=4 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # rollout new nginx image
  run kubectl set image deployment/nginx nginx=nginx:1.17-alpine --record
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

@test "kindbox service clusterIP" {

  run kubectl create deployment nginx --image=nginx:1.17-alpine
  [ "$status" -eq 0 ]

  run kubectl scale --replicas=4 deployment nginx
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # create a service and confirm it's there
  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  local svc_ip=$(k8s_svc_ip $cluster $controller default nginx)

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
    image: alpine
    args:
    - sleep
    - "1000000"
EOF

  k8s_create_pod $cluster $controller /tmp/alpine-sleep.yaml
  retry_run 10 3 "k8s_pod_ready $cluster $controller alpine-sleep"

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
  k8s_del_pod $cluster $controller alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kindbox service nodePort" {

  local num_workers=$(cat "$test_dir/."${cluster}"_num_workers")

  run kubectl create deployment nginx --image=nginx:1.17-alpine
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

  k8s_create_pod $cluster $controller /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready $cluster $controller alpine-sleep"

  run kubectl exec alpine-sleep -- sh -c "apk add curl"
  [ "$status" -eq 0 ]

  run sh -c 'kubectl exec alpine-sleep -- sh -c "curl -s \$NGINX_SERVICE_HOST" | grep -q "Welcome to nginx"'
  [ "$status" -eq 0 ]

  # cleanup
  k8s_del_pod k8s $controller alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

@test "kindbox DNS clusterIP" {

  # launch a deployment with an associated service

  run kubectl create deployment nginx --image=nginx:1.17-alpine
  echo "status = ${status}"
  echo "output = ${output}"
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

  k8s_create_pod $cluster $controller /tmp/alpine-sleep.yaml
  retry_run 10 2 "k8s_pod_ready $cluster $controller alpine-sleep"

  # find the cluster's DNS IP address
  run sh -c "kubectl get services --all-namespaces -o wide | grep kube-dns | awk '{print \$4}'"
  [ "$status" -eq 0 ]
  local dns_ip=$output

  # verify the pod has the cluster DNS server in its /etc/resolv.conf
  run sh -c "kubectl exec alpine-sleep -- sh -c \"cat /etc/resolv.conf\" | grep nameserver | awk '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" == "$dns_ip" ]

  # verify the pod can query the DNS server
  run kubectl exec alpine-sleep -- sh -c "nslookup nginx.default.svc.cluster.local"
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

  k8s_del_pod $cluster $controller alpine-sleep

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
  k8s_apply $cluster $controller $manifest_dir/traefik.yaml

  retry_run 40 2 "k8s_daemonset_ready $cluster $controller kube-system traefik-ingress-controller"

  # setup the ingress hostname in /etc/hosts
  local node_ip=$(k8s_node_ip ${cluster}-worker-0)
  echo "$node_ip traefik-ui.nestykube" >> /etc/hosts

  # verify ingress to traefik-ui works
  sleep 20

  wget traefik-ui.nestykube -O $test_dir/index.html
  grep Traefik $test_dir/index.html
  rm $test_dir/index.html

  # deploy nginx and create a service for it
  run kubectl create deployment nginx --image=nginx:1.16-alpine
  [ "$status" -eq 0 ]

  run kubectl scale --replicas=8 deployment nginx
  [ "$status" -eq 0 ]

  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

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
  k8s_apply $cluster $controller $test_dir/nginx-ing.yaml

  retry_run 40 2 "k8s_daemonset_ready $cluster $controller kube-system traefik-ingress-controller"

  # setup the ingress hostname in /etc/hosts
  local node_ip=$(k8s_node_ip ${cluster}-worker-1)
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

  rm $test_dir/nginx-ing.yaml

  # "cp + rm" because "mv" fails with "resource busy" as /etc/hosts is
  # a bind-mount inside the container
  cp /etc/hosts.orig /etc/hosts
  rm /etc/hosts.orig
}

@test "kindbox vol emptyDir" {

  # pod with two alpine containers sharing a couple of emptydir
  # volumes, one on-disk and one in-mem.
  cat > "$test_dir/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: multi-cont
spec:
  containers:
  - name: alpine1
    image: alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
    volumeMounts:
    - mountPath: /cache
      name: cache-vol
    - mountPath: /cache-mem
      name: cache-vol-mem
  - name: alpine2
    image: alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
    volumeMounts:
    - mountPath: /cache
      name: cache-vol
    - mountPath: /cache-mem
      name: cache-vol-mem
  volumes:
  - name: cache-vol
    emptyDir: {}
  - name: cache-vol-mem
    emptyDir:
      medium: Memory
EOF

  k8s_create_pod $cluster $controller "$test_dir/pod.yaml"
  retry_run 40 2 "k8s_pod_ready $cluster $controller multi-cont"

  # verify the emptyDir vol is shared correctly by containers (write
  # from one container, read from the other)

  run kubectl exec multi-cont -c alpine1 -- sh -c "echo hi > /cache/test"
  [ "$status" -eq 0 ]

  run kubectl exec multi-cont -c alpine2 -- cat /cache/test
  [ "$status" -eq 0 ]
  [ "$output" == "hi" ]

  run kubectl exec multi-cont -c alpine2 -- sh -c "echo hello > /cache-mem/test"
  [ "$status" -eq 0 ]

  run kubectl exec multi-cont -c alpine1 -- cat /cache-mem/test
  [ "$status" -eq 0 ]
  [ "$output" == "hello" ]

  # verify volume permissions inside pod look good
  run kubectl exec multi-cont -c alpine1 -- sh -c "ls -l / | grep -w cache | grep -v mem"
  [ "$status" -eq 0 ]
  verify_perm_owner "drwxrwxrwx" "root" "root" "$output"

  run kubectl exec multi-cont -c alpine2 -- sh -c "ls -l / | grep -w cache-mem"
  [ "$status" -eq 0 ]
  verify_perm_owner "drwxrwxrwt" "root" "root" "$output"

  #cleanup
  k8s_del_pod $cluster $controller multi-cont
  rm "$test_dir/pod.yaml"
}

@test "kindbox vol hostPath" {

  # create a directory and a file on the k8s-node; each will be
  # mounted as a hostPath vol into a pod
  docker exec "${cluster}"-worker-0 sh -c "mkdir -p /root/hpdir && echo hi > /root/hpdir/test"
  [ "$status" -eq 0 ]
  docker exec "${cluster}"-worker-0 sh -c "echo hello > /root/hpfile"
  [ "$status" -eq 0 ]

  # create a test pod with the hostPath vol; must be scheduled on
  # cluster-worker-0 since that's where the host volume is at.
cat > "$test_dir/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: hp-test
spec:
  nodeSelector:
    kubernetes.io/hostname: cluster1-worker-0
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

  k8s_create_pod $cluster $controller "$test_dir/pod.yaml"
  retry_run 40 2 "k8s_pod_ready $cluster $controller hp-test"

  # verify the pod sees the host volumes
  run sh -c "kubectl exec hp-test -- cat /hostdir/test"
  [ "$status" -eq 0 ]
  [ "$output" == "hi" ]

  run sh -c "kubectl exec hp-test -- cat /hostfile"
  [ "$status" -eq 0 ]
  [ "$output" == "hello" ]

  # write to the volume from the pod, verify the host sees the changes

  run sh -c "kubectl exec hp-test -- sh -c \"echo pod > /hostdir/pod-file\""
  [ "$status" -eq 0 ]
  run sh -c "kubectl exec hp-test -- sh -c \"echo pod > /hostfile\""
  [ "$status" -eq 0 ]

  docker exec "${cluster}"-worker-0 sh -c "cat /root/hpdir/pod-file"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  docker exec "${cluster}"-worker-0 sh -c "cat /root/hpfile"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  # verify volume permissions inside pod look good
  run sh -c "kubectl exec hp-test -- sh -c \"ls -l / | grep hostdir\""
  [ "$status" -eq 0 ]
  verify_perm_owner "drwxr-xr-x" "root" "root" "$output"

  run sh -c "kubectl exec hp-test -- sh -c \"ls -l / | grep hostfile\""
  [ "$status" -eq 0 ]
  verify_perm_owner "-rw-r--r--" "root" "root" "$output"

  #cleanup
  k8s_del_pod $cluster $controller hp-test

  docker exec "${cluster}"-worker-0 sh -c "rm -rf /root/hpdir && rm /root/hpfile"
  [ "$status" -eq 0 ]

  rm "$test_dir/pod.yaml"
}

@test "kindbox vol local persistent" {

  # based on:
  # https://www.alibabacloud.com/blog/kubernetes-volume-basics-emptydir-and-persistentvolume_594834

  # create backing dir on the host
  docker exec "${cluster}"-worker-0 sh -c "mkdir -p /mnt/pvol"
  [ "$status" -eq 0 ]

  docker exec "${cluster}"-worker-0 sh -c "echo data > /mnt/pvol/pfile"
  [ "$status" -eq 0 ]

  # create the persistent volume object and associated claim on the k8s cluster
  cat > "$test_dir/pvol.yaml" <<EOF
kind: PersistentVolume
apiVersion: v1
metadata:
  name: my-pvol
  labels:
    type: local
spec:
  persistentVolumeReclaimPolicy: Delete
  storageClassName: pv-demo
  capacity:
    storage: 10Mi
  accessModes:
    - ReadWriteOnce
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - cluster1-worker-0
  hostPath:
    path: "/mnt/pvol"
EOF

  cat > "$test_dir/pvol-claim.yaml" <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvol-claim
spec:
  storageClassName: pv-demo
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Mi
EOF

  k8s_apply $cluster $controller "$test_dir/pvol.yaml"
  k8s_apply $cluster $controller "$test_dir/pvol-claim.yaml"

  # create a test pod that mounts the persistent vol; k8s will automatically
  # schedule the pod on the node where the volume is created.
cat > "$test_dir/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pvol-test
spec:
  containers:
  - image: alpine
    name: alpine
    command: ['tail', '-f', '/dev/null']
    volumeMounts:
    - mountPath: /pvol
      name: pvol-test
  volumes:
  - name: pvol-test
    persistentVolumeClaim:
      claimName: pvol-claim
EOF

  k8s_create_pod $cluster $controller "$test_dir/pod.yaml"
  retry_run 40 2 "k8s_pod_ready $cluster $controller pvol-test"

  # verify pod can read/write volume
  run sh -c "kubectl exec pvol-test -- cat /pvol/pfile"
  [ "$status" -eq 0 ]
  [ "$output" == "data" ]

  run sh -c "kubectl exec pvol-test -- sh -c \"echo pod > /pvol/pfile\""
  [ "$status" -eq 0 ]

  run sh -c "kubectl exec pvol-test -- cat /pvol/pfile"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  # verify host sees volume changes done by pod
  docker exec "${cluster}"-worker-0 sh -c "cat /mnt/pvol/pfile"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  # delete the pod
  k8s_del_pod $cluster $controller pvol-test

  # create another instance of the pod
  k8s_create_pod $cluster $controller "$test_dir/pod.yaml"
  retry_run 40 2 "k8s_pod_ready $cluster $controller pvol-test"

  # verify pod sees prior changes (volume is persistent)
  run sh -c "kubectl exec pvol-test -- cat /pvol/pfile"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  # cleanup
  k8s_del_pod $cluster $controller pvol-test

  run sh -c "kubectl delete persistentvolumeclaims pvol-claim"
  [ "$status" -eq 0 ]

  run sh -c "kubectl delete persistentvolume my-pvol"
  [ "$status" -eq 0 ]

  docker exec "${cluster}"-worker-0 sh -c "rm -rf /mnt/pvol"
  [ "$status" -eq 0 ]

  rm "$test_dir/pod.yaml"
  rm "$test_dir/pvol-claim.yaml"
  rm "$test_dir/pvol.yaml"
}

# Verifies that pods get re-scheduled when a K8s node goes down
@test "kindbox node down" {

  # Customize a generic nginx deployment with a low 'tolerationSeconds' value,
  # such that when a node goes down, the pods get re-scheduled as quick as
  # possible -- by default this value matches 'pod-eviction-timeout' parameter,
  # which is set to 5 mins.
  cat > /tmp/nginx-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.17-alpine
        ports:
        - containerPort: 80
      tolerations:
      - key: "node.kubernetes.io/unreachable"
        operator: "Exists"
        effect: "NoExecute"
        tolerationSeconds: 2
      - key: "node.kubernetes.io/not-ready"
        operator: "Exists"
        effect: "NoExecute"
        tolerationSeconds: 2
EOF

  # Apply changes and wait for deployment components to be created.
  run kubectl apply -f /tmp/nginx-deployment.yaml
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # Export http port.
  run kubectl expose deployment/nginx --port 80
  [ "$status" -eq 0 ]

  # Obtain service's external ip.
  local svc_ip=$(k8s_svc_ip $cluster $controller default nginx)

  # Ensure app is reachable.
  retry_run 40 2 "docker exec $controller sh -c \"curl -s $svc_ip | grep -q \"Welcome to nginx\"\""
  [ "$status" -eq 0 ]

  # Check which worker node the pod is scheduled in
  run kubectl get pods --selector=app=nginx
  [ "$status" -eq 0 ]

  local pod=$(echo "${lines[1]}" | awk '{print $1}')
  local node=$(k8s_pod_node $cluster $controller $pod)

  # Delete that node from cluster.
  run kubectl delete node $node
  [ "$status" -eq 0 ]

  # Bring node container down.
  docker_stop "$node"
  [ "$status" -eq 0 ]

  # Eliminate node container. Instruction may fail if container was initialized
  # with docker "--rm" instruction.
  docker rm "$node"

  # K8s' controller will not react to node's elimination till
  # 'node-monitor-grace-period' interval (40 secs by default) has elapsed without
  # a response from the affected node. During this time k8s' control-plane will
  # continue displaying the pod as 'running'. Thus, we need to ensure that we wait
  # long enough for k8s to eliminate this pod (~60 secs + tolerationSeconds). More
  # details here: https://github.com/kubernetes-sigs/kubespray/blob/master/docs/kubernetes-reliability.md
  retry_run 40 2 "[ ! $(k8s_pod_in_node $cluster $controller $pod $node) ]"
  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # By now a new pod should have been scheduled, and its name should partially
  # match the name of the original pod (i.e. only the last 5 characters should
  # differ -- original pod: "nginx-64b55599df-nzpdc", new one: "nginx-64b55599df-nk56g").
  new_pod=${pod%?????}
  run sh -c "kubectl get pods --selector=app=nginx | awk '/$new_pod/ {print $1}'"
  [ "$status" -eq 0 ]
  [ ${#lines[@]} -eq 1 ]
  [ "$output" != "" ] && [ "$output" != "$pod" ]

  # Verify the service is back up too.
  retry_run 40 2 "docker exec $controller sh -c \"curl -s $svc_ip | grep -q \"Welcome to nginx\"\""

  # Bring the worker node back up.
  # (note: container name = container hostname = kubectl node name)

  local kubeadm_join=$(kubeadm_get_token $controller)

  docker_run --rm --name="$node" --hostname="$node" "$node_image"
  [ "$status" -eq 0 ]

  wait_for_inner_systemd $node

  docker exec "$node" sh -c "$kubeadm_join"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_node_ready $cluster $controller $node"

  # cleanup
  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployment nginx
  [ "$status" -eq 0 ]

  rm -rf /tmp/nginx-deployment.yaml
}

# Verifies Helm v2 proper operation.
@test "kindbox helm v2 basic" {

  # Install Helm V2.
  helm_v2_install $cluster $controller

  # Install an nginx ingress controller using a Helm chart
  docker exec $controller sh -c "helm install --name nginx-ingress stable/nginx-ingress --set rbac.create=true --set controller.service.type=NodePort"
  [ "$status" -eq 0 ]

  sleep 1

  # Verify Helm chart has been properly launched.
  docker exec $controller sh -c "helm ls | grep -q \"nginx-ingress\""
  [ "$status" -eq 0 ]

  run sh -c 'kubectl get pods -o wide | egrep -q "nginx-ingress"'
  [ "$status" -eq 0 ]

  local pod1_name=$(echo ${lines[1]} | awk '{print $1}')
  local pod2_name=$(echo ${lines[2]} | awk '{print $1}')

  # Wait till the new pods are fully up and running.
  retry_run 40 2 "k8s_pod_ready $cluster $controller $pod1_name"
  retry_run 40 2 "k8s_pod_ready $cluster $controller $pod2_name"

  # Verify that the ingress controller works
  verify_nginx_ingress $cluster $controller nginx-ingress-controller ${cluster}-worker-0

  # Cleanup
  docker exec $controller sh -c "helm ls --all --short | xargs -L1 helm delete --purge"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_cluster_is_clean $cluster $controller"

  docker exec $controller sh -c "helm ls | grep -q \"nginx-ingress\""
  [ "$status" -eq 1 ]

  # Uninstall Helm v2
  helm_v2_uninstall $cluster $controller
}

# Verifies Helm v3 proper operation.
@test "kindbox helm v3 basic" {

  # Install Helm V3.
  helm_v3_install $controller

  # Install new Helm chart for the nginx ingress controller; must set
  # its type to NodePort since we are not using a cloud load balancer
  # (or equivalent).
  docker exec $controller sh -c "helm install nginx-ingress stable/nginx-ingress --set rbac.create=true --set controller.service.type=NodePort"
  [ "$status" -eq 0 ]

  sleep 1

  # Install an nginx ingress controller using a Helm chart
  docker exec $controller sh -c "helm ls | grep -q \"nginx-ingress\""
  [ "$status" -eq 0 ]

  run kubectl get pods -o wide
  [ "$status" -eq 0 ]

  local pod1_name=$(echo ${lines[1]} | awk '{print $1}')
  local pod2_name=$(echo ${lines[2]} | awk '{print $1}')

  # Wait till the new pods are fully up and running.
  retry_run 40 3 "k8s_pod_ready $cluster $controller $pod1_name"
  retry_run 40 3 "k8s_pod_ready $cluster $controller $pod2_name"

  # Verify that the ingress controller works
  verify_nginx_ingress $cluster $controller nginx-ingress-controller ${cluster}-worker-0

  # Cleanup
  docker exec $controller sh -c "helm delete nginx-ingress"
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_cluster_is_clean $cluster $controller"

  # Verify the Helm chart is properly eliminated.
  docker exec $controller sh -c "helm ls | grep -q \"nginx-ingress\""
  [ "$status" -eq 1 ]

  # Uninstall Helm v3
  helm_v3_uninstall $controller
}

@test "kindbox cluster down" {

  local num_workers=$(cat "$test_dir/."${cluster}"_num_workers")

  kindbox_cluster_teardown $cluster

  remove_test_dir
}
