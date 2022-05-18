#!/usr/bin/env bats

# Tests for deploying a K8s cluster inside system container nodes and have them
# interconnected through flannel CNI.
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

# Preset kubeconfig env-var to point to the cluster-config file.
export KUBECONFIG=${HOME}/.kube/${cluster}-config

# Cluster's node image.
export k8s_version="v1.21.12"
export node_image="${CTR_IMG_REPO}/k8s-node-test:${k8s_version}"

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
# Bring k8s cluster up.
@test "kind cluster up (flannel)" {

  k8s_check_sufficient_storage

  create_test_dir

  kindbox_cluster_setup $cluster $num_workers $net $node_image $k8s_version

  # store k8s cluster info so subsequent tests can use it
  echo $num_workers > "$test_dir/."${cluster}"_num_workers"
}

# Testcase #2.
#
# Verify that a basic pod can be created and traffic forwarded accordingly.
@test "kind pod (flannel)" {

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
# Verify that a multi-container pod can be created and traffic forwarded
# accordingly.
@test "kind pod multi-container (flannel)" {

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
# Verify that deployment rollouts and scale up/down instructions work
# as expected.
@test "kind deployment (flannel)" {

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
# Verify that a clusterip service can properly expose a deployment and forward
# its traffic accordingly.
@test "kind service clusterIP (flannel)" {

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
# Verify that a nodeip service can properly expose a deployment and forward
# its traffic accordingly across all the cluster nodes.
@test "kind service nodePort (flannel)" {

  local num_workers=$(cat "$test_dir/."${cluster}"_num_workers")

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.17-alpine
  [ "$status" -eq 0 ]

  retry_run 40 2 "k8s_deployment_ready $cluster $controller default nginx"

  # create a nodePort service
  run kubectl expose deployment/nginx --port 80 --type NodePort
  [ "$status" -eq 0 ]

  sleep 5

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
# Verify that DNS operations work as expected within a deployment/pod and
# that queries are directed to the cluster DNS servers.
@test "kind DNS clusterIP (flannel)" {

  # launch a deployment with an associated service

  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.17-alpine
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

  k8s_del_pod alpine-sleep

  run kubectl delete svc nginx
  [ "$status" -eq 0 ]

  run kubectl delete deployments.apps nginx
  [ "$status" -eq 0 ]

  rm /tmp/alpine-sleep.yaml
}

# Testcase #8.
#
# Verify the proper operation of an ingress controller (traffik in this case).
@test "kind ingress (flannel)" {

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
  run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.16-alpine
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

# Testcase #9.
#
#
@test "kind vol emptyDir (flannel)" {

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
    image: ${CTR_IMG_REPO}/alpine
    command: ["tail"]
    args: ["-f", "/dev/null"]
    volumeMounts:
    - mountPath: /cache
      name: cache-vol
    - mountPath: /cache-mem
      name: cache-vol-mem
  - name: alpine2
    image: ${CTR_IMG_REPO}/alpine
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
  retry_run 40 2 "k8s_pod_ready multi-cont"

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

  # cleanup
  k8s_del_pod multi-cont
  rm "$test_dir/pod.yaml"
}

# Testcase #10.
#
#
@test "kind vol hostPath (flannel)" {

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
    kubernetes.io/hostname: cluster-1-worker-0
  containers:
  - image: ${CTR_IMG_REPO}/alpine
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
  retry_run 40 2 "k8s_pod_ready hp-test"

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
  k8s_del_pod hp-test

  docker exec "${cluster}"-worker-0 sh -c "rm -rf /root/hpdir && rm /root/hpfile"
  [ "$status" -eq 0 ]

  rm "$test_dir/pod.yaml"
}

# Testcase #11.
#
#
@test "kind vol local persistent (flannel)" {

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
          - cluster-1-worker-0
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
  - image: ${CTR_IMG_REPO}/alpine
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
  retry_run 40 2 "k8s_pod_ready pvol-test"

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
  k8s_del_pod pvol-test

  # create another instance of the pod
  k8s_create_pod $cluster $controller "$test_dir/pod.yaml"
  retry_run 40 2 "k8s_pod_ready pvol-test"

  # verify pod sees prior changes (volume is persistent)
  run sh -c "kubectl exec pvol-test -- cat /pvol/pfile"
  [ "$status" -eq 0 ]
  [ "$output" == "pod" ]

  # cleanup
  k8s_del_pod pvol-test

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

@test "kind cluster down (flannel)" {

  kindbox_cluster_teardown $cluster $net
  remove_test_dir
}
