#!/bin/bash

load ../helpers/run
load ../helpers/docker
load ../helpers/systemd
load ../helpers/fs
load ../helpers/k8s

# Wait for all worker nodes to be connected to master.
function rke2_all_nodes_ready() {
    local cluster=$1
    local num_workers=$2
    local delay=$3

    local timestamp=$(date +%s)
    local timeout=$(($timestamp + $delay))
    local all_ok

    while [ $timestamp -lt $timeout ]; do
        all_ok="true"

        for ((i = 1; i <= $num_workers; i++)); do
            master=${cluster}-master
            worker=${cluster}-worker-${i}

            run k8s_node_ready $worker
            if [ "$status" -ne 0 ]; then
                all_ok="false"
                break
            fi
        done

        if [[ "$all_ok" == "true" ]]; then
            break
        fi

        sleep 2
        timestamp=$(date +%s)
    done

    if [[ "$all_ok" != "true" ]]; then
        echo 1
    else
        echo 0
    fi
}

function rke2_cluster_setup() {
    local cluster=$1
    local num_workers=$2
    local rke2_version=$3
    local master_node=${cluster}-master
    local pubKey=$(cat ~/.ssh/id_rsa.pub)

    # Create master node and prepare ssh connectivity.
    docker_run --rm --name=${master_node} --hostname=${master_node} ${node_image}
    [ "$status" -eq 0 ]
    docker exec ${master_node} bash -c "mkdir -p ~/.ssh && echo $pubKey > ~/.ssh/authorized_keys"
    [ "$status" -eq 0 ]

    # Create worker nodes and prepare ssh connectivity.
    for i in $(seq 1 ${num_workers}); do
        local node=${cluster}-worker-${i}

        docker_run --rm --name=${node} --hostname=${node} ${node_image}
        [ "$status" -eq 0 ]

        docker exec ${node} bash -c "mkdir -p ~/.ssh && echo $pubKey > ~/.ssh/authorized_keys"
        [ "$status" -eq 0 ]
    done

    wait_for_inner_systemd ${master_node}

    # Controller's rke2 installation.
    docker exec ${master_node} bash -c "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=$rke2_version sh -"
    [ "$status" -eq 0 ]
    docker exec ${master_node} bash -c "systemctl enable rke2-server.service && systemctl start rke2-server.service"
    [ "$status" -eq 0 ]

    sleep 10

    # Obtain controller's ip address.
    docker exec ${master_node} bash -c "ip address show dev eth0 | grep inet | cut -d\"/\" -f1 | awk '{print \$2}'"
    [ "$status" -eq 0 ]
    local controller_ip=${output}

    # Obtain controller's k8s token.
    docker exec ${master_node} cat /var/lib/rancher/rke2/server/node-token
    [ "$status" -eq 0 ]
    local k8s_token=${output}

    # Configure and initialize control-plane in worker nodes.

    cat >"config.yaml" <<EOF
server: https://${controller_ip}:9345
token: ${k8s_token}
EOF

    for i in $(seq 1 ${num_workers}); do
        local node=${cluster}-worker-${i}

        docker exec ${node} bash -c "mkdir -p /etc/rancher/rke2"
        [ "$status" -eq 0 ]
        docker cp config.yaml ${node}:/etc/rancher/rke2/config.yaml
        [ "$status" -eq 0 ]

        docker exec ${node} bash -c "curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_VERSION=$rke2_version sh -"
        [ "$status" -eq 0 ]
        docker exec ${node} bash -c "systemctl enable rke2-agent.service && systemctl start rke2-agent.service"
        [ "$status" -eq 0 ]
    done

    run rm -rf config.yaml
    [ "$status" -eq 0 ]

    # Set KUBECONFIG path.
    export KUBECONFIG=/root/nestybox/sysbox/kubeconfig
    [ "$status" -eq 0 ]
    kubectl config set-context default
    [ "$status" -eq 0 ]
    docker cp ${master_node}:/etc/rancher/rke2/rke2.yaml kubeconfig
    [ "$status" -eq 0 ]
    run sed -i "s/127.0.0.1/${controller_ip}/" kubeconfig
    [ "$status" -eq 0 ]

    local join_timeout=$(($num_workers * 30))
    rke2_all_nodes_ready $cluster $num_workers $join_timeout

    # Wait till all kube-system pods have been initialized.
    retry_run 60 5 "k8s_pods_ready kube-system"
}

# Tears-down a rke2 cluster created with rke2_cluster_setup().
#
function rke2_cluster_teardown() {
    local cluster=$1
    local num_workers=$2

    for i in $(seq 1 ${num_workers}); do
        node=${cluster}-worker-${i}

        docker stop -t0 ${node} 2>&1
        [ "$status" -eq 0 ]
    done

    docker stop -t0 ${cluster}-master
    [ "$status" -eq 0 ]

    rm -rf ${KUBECONFIG}
}
