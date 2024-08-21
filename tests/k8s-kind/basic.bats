#!/usr/bin/env bats

#
# Basic tests for K8s.io KinD + Sysbox
#
# NOTE: these tests assume Docker uses Sysbox as the default runtime, which is
# the case for the Sysbox test container. There's currently no other way to tell
# KinD to use Sysbox as the runtime.
#

load ../helpers/run
load ../helpers/docker
load ../helpers/k8s
load ../helpers/sysbox
load ../helpers/environment
load ../helpers/sysbox-health

function kind_installed() {
  if command -v kind &> /dev/null; then
    return 0
  else
    return 1
  fi
}

function setup() {
  if ! kind_installed; then
    skip "kind tool not installed."
  fi
}

function teardown() {
  sysbox_log_check
}

@test "basic k8s.io kind cluster" {

  # setup the cluster config (3 nodes)
  test_dir=$(mktemp -d)
  cat > "${test_dir}/kind-cluster-config.yaml" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

  # create the kind cluster
  kind create cluster --wait 40s --config ${test_dir}/kind-cluster-config.yaml
  kubectl cluster-info --context kind-kind

  # verify it uses sysbox containers
  for node_name in "kind-control-plane" "kind-worker" "kind-worker2"; do
    docker inspect --format {{.HostConfig.Runtime}} $node_name
    [ "$status" -eq 0 ]
    [[ "$output" == "sysbox-runc" ]]
  done

  # create a pod
  cat > "${test_dir}/basic-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: ${CTR_IMG_REPO}/nginx
EOF

  k8s_create_pod "${test_dir}/basic-pod.yaml"
  retry_run 30 2 "k8s_pod_ready nginx"

  # verify the pod is healthy
  local pod_ip=$(k8s_pod_ip nginx)
  docker exec kind-control-plane sh -c "curl -s $pod_ip | grep -q \"Welcome to nginx\""
  [ "$status" -eq 0 ]

  # cleanup
  k8s_del_pod nginx
  rm -r "${test_dir}"
  kind delete cluster
}
