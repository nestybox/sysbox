#!/usr/bin/env bats

#
# Tests for running K8s in side a sysbox pods.
#
# TODO:
#
# - Add check for sufficient host storage check before k8s-in-pod test
# - Cleanup all crictl images after tests
# - Refactor kindbox.bats tests so we can use all those same tests when running k8s-in-pod

load ../helpers/crio
load ../helpers/userns
load ../helpers/k8s
load ../helpers/run
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# Verify K8s works correctly inside a sysbox pod
@test "k8s-in-pod" {

	# Create the k8s master and worker nodes
	local k8s_master_syscont=$(crictl_run ${POD_MANIFEST_DIR}/k8s-master-container.json ${POD_MANIFEST_DIR}/k8s-master-pod.json)
	local k8s_master_pod=$(crictl_cont_get_pod $k8s_master_syscont)

	local k8s_worker_syscont=$(crictl_run ${POD_MANIFEST_DIR}/k8s-worker-container.json ${POD_MANIFEST_DIR}/k8s-worker-pod.json)
	local k8s_worker_pod=$(crictl_cont_get_pod $k8s_worker_syscont)

	# Wait for systemd to boot on the nodes
	sleep 10

	run crictl exec $k8s_master_syscont sh -c "systemctl status"
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" =~ "State: running" ]]

	run crictl exec $k8s_worker_syscont sh -c "systemctl status"
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" =~ "State: running" ]]

	# Initialize the K8s master pod
	crictl exec $k8s_master_syscont sh -c "kubeadm init --kubernetes-version=v1.18.2 --pod-network-cidr=10.244.0.0/16"

	# Configure kubectl to talk to inner K8s cluster
	crictl_kubectl_config $k8s_master_syscont "inner-cluster"

	run kubectl get all
	echo "$output" | grep "ClusterIP"

	kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
	retry_run 40 2 "k8s_node_ready k8s-master"

	# Join the k8s worker pod to the inner-cluster
	join_cmd=$(crictl exec $k8s_master_syscont sh -c "kubeadm token create --print-join-command 2> /dev/null")
	crictl exec $k8s_worker_syscont sh -c "$join_cmd"
	retry_run 40 2 "k8s_node_ready k8s-worker"

	# Create a basic deployment and verify all is well
 	local cluster_name="inner-cluster"
 	export KUBECONFIG=${KUBECONFIG}:${HOME}/.kube/${cluster_name}-config
 	kubectl config use-context kubernetes-admin@${cluster_name}

	run kubectl create deployment nginx --image=${CTR_IMG_REPO}/nginx:1.16-alpine
	[ "$status" -eq 0 ]

	retry_run 40 2 "k8s_deployment_ready inner-cluster k8s-master default nginx"

	run kubectl scale --replicas=4 deployment nginx
	[ "$status" -eq 0 ]

	retry_run 40 2 "k8s_deployment_ready inner-cluster k8s-master default nginx"

	run kubectl scale --replicas=1 deployment nginx
	[ "$status" -eq 0 ]

	retry_run 40 2 "k8s_deployment_ready inner-cluster k8s-master default nginx"

	run kubectl delete deployments.apps nginx
	[ "$status" -eq 0 ]

	# Cleanup
	crictl stopp $k8s_master_pod $k8s_worker_pod
	crictl rmp $k8s_master_pod $k8s_worker_pod
}
