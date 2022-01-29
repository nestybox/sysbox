#!/usr/bin/env bats

#
# Verify running a prometheus container inside a sys container
#

load ../../helpers/run
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function wait_for_inner_dockerd() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

function wait_for_prometheus() {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME sh -c \"docker ps --format \"{{.Status}}\" | grep \"Up\"\""
  sleep 10
}

@test "l2 prometheus basic" {

  # Inside the sys container, deploys a prometheus container and verifies it's up & running

  cat > ${HOME}/prometheus.yml <<EOF
# scrape config for the Prometheus server itself
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 2s
    static_configs:
      - targets: ['localhost:9090']
EOF

  # launch a sys container
  SYSCONT_NAME=$(docker_run --rm \
                 --mount type=bind,source="${HOME}"/prometheus.yml,target=/root/prometheus.yml \
                 ${CTR_IMG_REPO}/test-syscont:latest tail -f /dev/null)

  # launch docker inside the sys container
  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd

  # launch the inner prometheus container
  docker exec "$SYSCONT_NAME" sh -c "docker load -i /root/img/prometheus.tar"
  docker exec "$SYSCONT_NAME" sh -c "docker run -d --rm --name prometheus \
                                     --mount type=bind,source=/root/prometheus.yml,target=/etc/prometheus/prometheus.yml \
                                     -p 9090:9090 \
                                     prom/prometheus"
  [ "$status" -eq 0 ]

  wait_for_prometheus

  # query prometheus
  docker exec "$SYSCONT_NAME" sh -c "curl -s http://localhost:9090/api/v1/targets"
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"job":"prometheus"'.+'"health":"up"' ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}
