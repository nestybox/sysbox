#!/usr/bin/env bats

#
# Verify proper operation of a drone-server inside a sysbox container.
#

load ../../helpers/run

function wait_for_init() {
    retry_run 5 1 eval "__docker exec drone ps -ef | grep -e "dockerd" -e "drone""
}

@test "drone ci/cd pipeline execution" {

    # Deploys a drone-server within a sysbox container.

    # As part of this test we will execute a ci/cd pipeline defined within a
    # (dummy) VCS repository: nestybox/drone-with-go. To reach this pipeline
    # configuration, we must git-clone this repo, so that its content can be
    # accessible throughout the various drone pipeline stages.
    tmpdir="/root/drone"
    mkdir -p ${tmpdir}
    cd ${tmpdir}
    run git clone https://github.com/nestybox/drone-with-go.git
    [ "$status" -eq 0 ]

    # Launch drone-server container (L1 sysbox container).
    SYSCONT_NAME=$(docker_run \
                    --env=DRONE_GITHUB_SERVER=https://github.com \
                    --env=DRONE_GITHUB_CLIENT_ID=da96f2063301a68186ed \
                    --env=DRONE_GITHUB_CLIENT_SECRET=46fcb24fe84b5b738a2954b40ecf03ece38dd1a1 \
                    --env=DRONE_RUNNER_CAPACITY=2 \
                    --env=DRONE_SERVER_HOST=localhost \
                    --env=DRONE_SERVER_PROTO=https \
                    --env=DRONE_TLS_AUTOCERT=true \
                    --env=DRONE_SERVER=http://localhost:80 \
                    --env=DRONE_TOKEN=55f24eb3d61ef6ac5e83d55017860000 \
                    --env=DRONE_USER_CREATE=username:nestybox,admin:true,token:55f24eb3d61ef6ac5e83d55017860000 \
                    --publish=80:80 --publish=443:443 \
                    --mount type=bind,source=${tmpdir}/drone-with-go,target=/root/drone-with-go \
                    -d --rm --name=drone nestybox/ubuntu-bionic-drone-server)

    wait_for_init

    # Every pipeline stage is executed within an L2 container instantiated
    # by the drone-server daemon. This particular pipeline consists of the
    # following steps:
    #
    #   * Test: go test ...
    #   * Build: go build ...
    #   * Image-build: docker build ...
    #
    run docker exec drone sh -c "cd /root/drone-with-go && drone exec --trusted"
    echo "status = ${status}"
    echo "output = ${output}"
    [ "$status" -eq 0 ]

    # Cleanup
    docker_stop "$SYSCONT_NAME"
    [ "$status" -eq 0 ]

    rm -rf ${tmpdir}
}
