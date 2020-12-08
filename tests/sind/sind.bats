# Testing for sysbox-in-docker

load ../helpers/run
load ../helpers/docker
load ../helpers/environment
load ../helpers/sysbox-health

export docker_cfgfile_bak="/etc/docker/daemon.json.bak"

export distro=$(get_distro)
export release=$(get_release)

@test "sysbox-in-docker build" {
   make sysbox-in-docker-local ${distro}-${release}
}

@test "sysbox-in-docker basic" {

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
}

@test "sysbox-in-docker syscont-with-systemd-docker" {

   docker run -d --privileged --rm \
          --name sind --hostname sind \
          -v /mnt/scratch/sind-var-lib-docker:/var/lib/docker \
          -v /mnt/scratch/sind-var-lib-sysbox:/var/lib/sysbox \
          -v /lib/modules/$(uname -r):/lib/modules/$(uname -r):ro \
          -v /usr/src/linux-headers-$(uname -r):/usr/src/linux-headers-$(uname -r):ro \
          -v /usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):/usr/src/linux-headers-$(uname -r | cut -d"-" -f 1,2):ro \
          nestybox/sysbox-in-docker:${distro}-${release} tail -f /dev/null

   wait_for_inner_dockerd sind

   docker exec sind sh -c "docker run --name inner --runtime=sysbox-runc -d --rm nestybox/ubuntu-focal-systemd-docker"
   [ "$status" -eq 0 ]

   # TODO: for some reason the following retry does not work; fix this.
   # retry_run 10 1 "__docker exec sind sh -c \"docker exec inner sh -c \"docker ps\"\""
   sleep 10

   docker exec sind sh -c "docker exec inner sh -c \"docker run hello-world | grep \"Hello from Docker!\"\""
   [ "$status" -eq 0 ]

   docker stop -t0 sind
   [ "$status" -eq 0 ]
}
