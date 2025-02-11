#!/usr/bin/env bats

#
# Test for building container images with Paketo buildpacks + Docker + Sysbox.
#
# NOTE: assumes Docker is configured to use Sysbox as the runtime
# for builds. This is done by setting env var "DOCKER_BUILDKIT_RUNC_COMMAND=/usr/bin/sysbox-runc"
# when starting Docker Engine inside the Sysbox test conatainer (supported since Docker Engine v25.0).
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health
load ../helpers/environment

function teardown() {
  sysbox_log_check
}

@test "paketo build basic" {

	if ! command -v pack &> /dev/null; then
	  skip "requires the Paketo pack cli to be installed"
	fi

  local tmpdir=$(mktemp -d)

	# create golang program in test dir
	cat > $tmpdir/main.go << EOF
package main

import "fmt"

func main() {
    fmt.Println("Hello, Paketo Buildpacks!")
}
EOF

	# build the image with buildpack
	cd $tmpdir && pack build my-go-app --builder paketobuildpacks/builder-jammy-tiny

	# verify result
	docker run --rm my-go-app
  [ "$status" -eq 0 ]
  [[ "$output" == "Hello, Paketo Buildpacks!" ]]

	# cleanup
	docker image rm my-go-app
	rm -r $tmpdir
}
