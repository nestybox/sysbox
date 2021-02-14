# Testing for sysbox-in-docker

load ../helpers/run
load ../helpers/docker
load ../helpers/environment
load ../helpers/sysbox-health

export docker_cfgfile_bak="/etc/docker/daemon.json.bak"

export distro=$(get_distro)
export release=$(get_release)

@test "sind build" {
   make sysbox-in-docker-local ${distro}-${release}
}

@test "sind basic" {

   docker run -d --privileged --rm \
          --name sind --hostname sind \
          -v /mnt/scratch/sind-var-lib-docker:/var/lib/docker \
          -v /mnt/scratch/sind-var-lib-sysbox:/var/lib/sysbox \
          -v /lib/modules/$(uname -r):/lib/modules/$(uname -r):ro \
          -v /usr/src/linux-headers-$(uname -r):/usr/src/linux-headers-$(uname -r):ro \
          -v /usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):/usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):ro \
          nestybox/sysbox-in-docker:${distro}-${release} tail -f /dev/null

   wait_for_inner_dockerd sind

   docker exec sind sh -c "docker run --runtime=sysbox-runc hello-world"
   [ "$status" -eq 0 ]

   docker stop -t0 sind
   [ "$status" -eq 0 ]

   rm -rf /mnt/scratch/sind-var-lib-docker
   rm -rf /mnt/scratch/sind-var-lib-sysbox
}

@test "sind syscont-with-systemd-docker" {

   docker run -d --privileged --rm \
          --name sind --hostname sind \
          -v /mnt/scratch/sind-var-lib-docker:/var/lib/docker \
          -v /mnt/scratch/sind-var-lib-sysbox:/var/lib/sysbox \
          -v /lib/modules/$(uname -r):/lib/modules/$(uname -r):ro \
          -v /usr/src/linux-headers-$(uname -r):/usr/src/linux-headers-$(uname -r):ro \
          -v /usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):/usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):ro \
          nestybox/sysbox-in-docker:${distro}-${release} tail -f /dev/null

   wait_for_inner_dockerd sind

   docker exec sind sh -c "docker run --name inner --runtime=sysbox-runc -d --rm ${CTR_IMG_REPO}/ubuntu-focal-systemd-docker"
   [ "$status" -eq 0 ]

   # TODO: for some reason the following retry does not work; thus we opt for a
   # conservative delay to allow the container to be ready.

   # retry_run 10 1 "__docker exec sind sh -c \"docker exec inner sh -c \"docker ps\"\""
   sleep 10

   docker exec sind sh -c "docker exec inner sh -c \"docker run hello-world | grep \"Hello from Docker!\"\""
   [ "$status" -eq 0 ]

   docker stop -t0 sind
   [ "$status" -eq 0 ]

   rm -rf /mnt/scratch/sind-var-lib-docker
   rm -rf /mnt/scratch/sind-var-lib-sysbox
}

@test "multiple sind sysctl collision" {
   local num_sind=4
   local max_sind=$(($num_sind-1))

   for i in `seq 0 $max_sind`; do
      docker run -d --privileged --rm \
             --name sind${i} --hostname sind${i} \
             -v /mnt/scratch/sind${i}-var-lib-docker:/var/lib/docker \
             -v /mnt/scratch/sind${i}-var-lib-sysbox:/var/lib/sysbox \
             -v /lib/modules/$(uname -r):/lib/modules/$(uname -r):ro \
             -v /usr/src/linux-headers-$(uname -r):/usr/src/linux-headers-$(uname -r):ro \
             -v /usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):/usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):ro \
             nestybox/sysbox-in-docker:${distro}-${release} tail -f /dev/null
   done

   for i in `seq 0 $max_sind`; do
      wait_for_inner_dockerd sind${i}
   done

   for i in `seq 0 $max_sind`; do
      docker exec sind${i} sh -c "docker run --name inner --runtime=sysbox-runc -d --rm ${CTR_IMG_REPO}/alpine tail -f /dev/null"
      [ "$status" -eq 0 ]

      docker exec sind${i} sh -c "docker exec inner sh -c \"apk update && apk add bash\""
      [ "$status" -eq 0 ]
   done

   # The test script below will be copied to the sys container running inside
   # the privileged sysbox-in-docker container. This will cause each sys
   # container to write conflicting values to nf_conntrack_max concurrently.
   # This in turn will cause the sysbox instances (one in each privileged
   # container) to want to write conflicting values to the kernel. The sysbox
   # instances use a heuristic that ensures that the value programmed into the
   # kernel will always be the max across these values.

   local test_scr=$(tempfile)

cat > $test_scr <<EOF
    #!/bin/bash
    iter=\$1
    delay=\$2
    val=\$3

    for i in \$(seq 1 \$iter); do
        sleep \$delay
        echo \$val > /proc/sys/net/netfilter/nf_conntrack_max
        res=\$(cat /proc/sys/net/netfilter/nf_conntrack_max)
        if [ \$res -ne \$val ]; then
           echo "sysctl mismatch: want \$val, got \$res"
           exit 1
        fi
    done
EOF

   chmod +x $test_scr

   # Copy the test script to each sys container
   for i in `seq 0 $max_sind`; do
      docker cp $test_scr sind${i}:/tmp/write_to_sysctl
      [ "$status" -eq 0 ]

      docker exec sind${i} sh -c "docker cp /tmp/write_to_sysctl inner:/bin"
      [ "$status" -eq 0 ]
   done

   # Remember the host's orig value (we will revert it later)
   local orig_val=$(cat /proc/sys/net/netfilter/nf_conntrack_max)

   # Start the test script in each sys container
   for i in `seq 0 $max_sind`; do

      local iter=20
      local delay=$(printf "0.%d\n" $((1 + $RANDOM % 10)))
      local val=$(($orig_val + 10 + $i))

      docker exec sind${i} sh -c "docker exec -d inner sh -c \"write_to_sysctl $iter $delay $val\""
      [ "$status" -eq 0 ]

   done

   # Wait for test to complete
   sleep $num_sind

   # For nf_conntrack_max, we expect the value written to the kernel to be the
   # largest among the values written by all sysbox containers.
   local end_val=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
   [ $end_val -eq $(($orig_val + 10 + $max_sind)) ]

   # Cleanup
   for i in `seq 0 $max_sind`; do
      docker stop -t0 sind${i}
      [ "$status" -eq 0 ]
      rm -rf /mnt/scratch/sind${i}-var-lib-docker
      rm -rf /mnt/scratch/sind${i}-var-lib-sysbox
   done
   rm $test_scr
   echo $orig_val > /proc/sys/net/netfilter/nf_conntrack_max
}
