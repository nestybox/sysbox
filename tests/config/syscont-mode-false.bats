#!/usr/bin/env bats

#
# Verify the Sysbox "syscont-mode=false" config (i.e., to run regular containers
# instead of system containers)
#

load ../helpers/run
load ../helpers/docker
load ../helpers/environment
load ../helpers/sysbox
load ../helpers/sysbox-health
load ../helpers/mounts
load ../helpers/userns
load ../helpers/cgroups
load ../helpers/uid-shift

function teardown() {
  sysbox_log_check
}

function wait_for_status_up() {
  retry_run 5 1 eval "__docker ps --format \"{{.Status}}\" | grep \"Up\""
}

@test "syscont-mode=false: basic" {

	local syscont=$(docker_run --runtime=sysbox-runc \
										-e "SYSBOX_SYSCONT_MODE=FALSE" \
										--rm \
										${CTR_IMG_REPO}/alpine tail -f /dev/null)

	# Verify process caps are honored
	local docker_ver=$(docker_engine_version)
	local expectedCapInh="00000000a80425fb"
	if semver_ge $docker_ver "20.10.14"; then
		expectedCapInh="0000000000000000"
	fi

	docker exec "$syscont" sh -c "cat /proc/1/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"$expectedCapInh" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	# Verify read-only mounts: normally sysbox mounts these "rw", but should be
	# "ro" when SYSBOX_SYSCONT_MODE=false.

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /proc/sys type fuse (ro"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysfs on /sys type sysfs (ro"'
	[ "$status" -eq 0 ]

	if host_is_cgroup_v2; then
		docker exec "$syscont" sh -c 'mount | grep "cgroup on /sys/fs/cgroup type cgroup2 (ro"'
		[ "$status" -eq 0 ]
	else
		docker exec "$syscont" sh -c 'mount | grep "/sys/fs/cgroup/"'
		[ "$status" -eq 0 ]
		for line in "${lines[@]}"; do
			echo "$line" | grep "ro,"
		done
	fi

	# Verify masked paths: normally sysbox exposes these, but should be masked
	# when SYSBOX_SYSCONT_MODE=false.

	docker exec "$syscont" sh -c "mount | grep 'tmpfs on /proc/kcore'"
	[ "$status" -eq 0 ]

	# Verify implicit mounts: normally sysbox mounts these, but should not be
	# mounted when SYSBOX_SYSCONT_MODE=false

	# Implicit mounts on special dirs should not present
	for m in "${syscont_special_dirs}"; do
		docker exec "$syscont" sh -c "mount | grep \"on $m\""
		[ "$status" -ne 0 ]
	done

	# Implicit kernel header mount should not be present
	local kernel_rel=$(uname -r)

	docker exec "$syscont" sh -c "mount | grep \"/usr/src/kernels/${kernel_rel}\""
	[ "$status" -ne 0 ]
	docker exec "$syscont" sh -c "mount | grep \"/usr/src/linux-headers-${kernel_rel}\""
	[ "$status" -ne 0 ]

	# Implicit /lib/modules/<kernel> mount should not be present
	docker exec "$syscont" sh -c "mount | grep \"/lib/modules/${kernel_rel}\""
	[ "$status" -ne 0 ]

	# Verify seccomp filter: normally sysbox allows these syscalls, but they should
	# be blocked when SYSBOX_SYSCONT_MODE=false
	docker exec "$syscont" sh -c "mkdir /root/tmp && mount -t tmpfs -o size=64K tmpfs /root/tmp"
	[ "$status" -eq 1 ]
	docker exec "$syscont" sh -c "umount /etc/resolv.conf"
	[ "$status" -eq 1 ]
	docker exec "$syscont" sh -c "unshare -m sh"
	[ "$status" -eq 1 ]

	# TODO: verify AppArmor profile is enforced when SYSBOX_SYSCONT_MODE=false;
	# currently this is hard to do within the test container because it's a
	# privileged container so all processes within it are not under AppArmor.

	docker_stop $syscont
}

@test "syscont-mode=false: exec" {

	# verify the SYSBOX_SYSCONT_MODE env var is fixed at container start time; it
	# can't be changed in "docker exec" (i.e., sysbox ignores it).

	local syscont=$(docker_run --runtime=sysbox-runc \
										-e "SYSBOX_SYSCONT_MODE=FALSE" \
										--rm \
										${CTR_IMG_REPO}/alpine tail -f /dev/null)

	local docker_ver=$(docker_engine_version)
	local expectedCapInh="00000000a80425fb"
	if semver_ge $docker_ver "20.10.14"; then
		expectedCapInh="0000000000000000"
	fi

	docker exec "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"$expectedCapInh" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker exec -e "SYSBOX_SYSCONT_MODE=TRUE" "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]

	[[ "${lines[0]}" =~ "CapInh:".+"$expectedCapInh" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker_stop $syscont
}

@test "syscont-mode=false: no systemd setup" {

	# Verify Sysbox does no special systemd set up on the container when honoring
	# OCI (this causes systemd to fail to init).

	local syscont=$(docker_run --runtime=sysbox-runc \
										-e "SYSBOX_SYSCONT_MODE=FALSE" \
										--rm \
										${CTR_IMG_REPO}/ubuntu-focal-systemd-docker)

	docker exec "$syscont" sh -c "mount | grep '/sys/kernel/config'"
	[ "$status" -eq 1 ]

	docker exec "$syscont" sh -c "systemctl status"
	[ "$status" -eq 1 ]

	docker_stop $syscont
}

@test "syscont-mode=false: bind mount id-shift" {

	# Verify host dirs/files bind-mounted into container are ID-shifted properly,
	# even if SYSBOX_SYSCONT_MODE=false.

	docker volume rm testVol
	docker volume create testVol
	[ "$status" -eq 0 ]

	local syscont=$(docker_run --runtime=sysbox-runc \
										-e "SYSBOX_SYSCONT_MODE=FALSE" \
										-v testVol:/mnt/testVol \
										--rm \
										${CTR_IMG_REPO}/alpine tail -f /dev/null)

	docker exec "$syscont" sh -c "mount | grep testVol"
	[ "$status" -eq 0 ]

	if docker_userns_remap; then
		[[ "$output" =~ "/dev".+"on /mnt/testVol" ]]
	elif sysbox_using_shiftfs_only; then
		[[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"on /mnt/testVol type shiftfs" ]]
	elif sysbox_using_idmapped_mnt_only; then
		[[ "$output" =~ "idmapped" ]]
	elif sysbox_using_all_uid_shifting; then
		[[ "$output" =~ "idmapped" ]]
	else
		[[ "$output" =~ "/dev".+"on /mnt/testVol" ]]
	fi

	docker_stop $syscont
	docker volume rm testVol
}

@test "syscont-mode=false: bind mount over special dir" {

	# Verify host dirs/files bind-mounted into the container's special dir are
	# chowned properly, even if SYSBOX_SYSCONT_MODE=false.

	testDir="/root/var-lib-docker"
	rm -rf ${testdir}
	mkdir -p ${testDir}

	local syscont=$(docker_run -e "SYSBOX_SYSCONT_MODE=FALSE" \
										--rm \
										-v ${testDir}:/var/lib/docker \
										${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	docker exec "$syscont" sh -c "findmnt | grep \"\/var\/lib\/docker  \""
	[ "$status" -eq 0 ]

	line=$(echo $output | tr -s ' ')
	mountSrc=$(echo "$line" | cut -d" " -f 2)
	mountFs=$(echo "$line" | cut -d" " -f 3)

	[[ "$mountSrc" =~ "$testDir" ]]
	[[ "$mountFs" != "shiftfs" ]]
	echo $line | grep -qv "idmapped"

	# Verify sysbox changed the permissions on the mount source (unless they are ID-mapped)
	tuid=$(stat -c %u "$testDir")
	tgid=$(stat -c %g "$testDir")

	if ! sysbox_using_overlayfs_on_idmapped_mnt; then
		uid=$(__docker exec "$syscont" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
		gid=$(__docker exec "$syscont" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
		[ "$uid" -eq "$tuid" ]
		[ "$gid" -eq "$tgid" ]
	else
		tuid=0
		tgid=0
	fi

	docker_stop $syscont
	rm -r ${testDir}
}

@test "syscont-mode=false: per-container" {

	# Verify process caps are honored for the container with SYSBOX_SYSCONT_MODE
	# set, but not for the other one.

	local sc1=$(docker_run --runtime=sysbox-runc \
								  -e "SYSBOX_SYSCONT_MODE=FALSE" \
								  --rm \
								  ${CTR_IMG_REPO}/alpine tail -f /dev/null)

	local sc2=$(docker_run --runtime=sysbox-runc \
								  -e "SYSBOX_SYSCONT_MODE=TRUE" \
								  --rm \
								  ${CTR_IMG_REPO}/alpine tail -f /dev/null)

	local docker_ver=$(docker_engine_version)
	local expectedCapInh="00000000a80425fb"
	if semver_ge $docker_ver "20.10.14"; then
		expectedCapInh="0000000000000000"
	fi

	docker exec "$sc1" sh -c "cat /proc/1/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"$expectedCapInh" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	local root_caps=$(get_root_capabilities)

	docker exec "$sc2" sh -c "cat /proc/1/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"$root_caps" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"$root_caps" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"$root_caps" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"$root_caps" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"$root_caps" ]]

	docker_stop $sc1
	docker_stop $sc2
}

@test "syscont-mode=false: with --privileged" {

	# A container with SYSBOX_SYSCONT_MODE=FALSE but "--privileged" is interesting:
	# Docker relaxes constraints on it (e.g., mounts /proc rw, removes seccomp,
	# mounts all host devs, etc.), yet the container is not really privileged at
	# host level because Sysbox enables the user-ns on it, virtualizes portions
	# of /proc and /sys, and traps certain syscalls. This means the container
	# can't access non-namespaced resources under /proc or /dev for example.
	#
	# In fact, this combination approaches a regular system container except a
	# system container carries other setups that allow it to run system workloads
	# too (e.g., systemd, docker, k8s, etc.)

	docker volume rm testVol
	docker volume create testVol
	[ "$status" -eq 0 ]

	local syscont=$(docker_run --runtime=sysbox-runc \
										-e "SYSBOX_SYSCONT_MODE=FALSE" \
										--privileged \
										--rm \
										-v testVol:/mnt/testVol \
										${CTR_IMG_REPO}/alpine tail -f /dev/null)

	local syscont_pid=$(docker_cont_pid $syscont)
	container_is_rootless $syscont_pid "sysbox"

	local root_caps=$(get_root_capabilities)
	docker exec "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000000000000000" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"$root_caps" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"$root_caps" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"$root_caps" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker exec "$syscont" sh -c 'mount | grep "proc on /proc type proc (rw"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /proc/swaps type fuse (rw"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /proc/sys type fuse (rw"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /proc/uptime type fuse (rw"'
	[ "$status" -eq 0 ]

	# Verify sysbox traps the mount syscall still
	docker exec "$syscont" sh -c "mkdir /root/proc && mount -t proc proc /root/proc"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /root/proc/swaps type fuse (rw"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /root/proc/sys type fuse (rw"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /root/proc/uptime type fuse (rw"'
	[ "$status" -eq 0 ]

	# Verify immutable mounts work (with runc this would pass since container is
	# privileged; with sysbox it will fail because for security reasons all
	# mounts that make the container are immutable, always).
	#
	# XXX: the failure code varies when id-mapping is used on the mount on kernel
	# 5.19 (e.g., fails with "invalid argument" as opposed to "permission
	# denied"). Need to investigate why, but for now just look for a non-zero
	# error code.

	docker exec "$syscont" sh -c 'mount -o remount,rw /mnt/testVol'
	[ "$status" -ne 0 ]

	# Verify *xattr syscalls are not trapped in this case
	docker exec "$syscont" sh -c "apk add attr"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "touch /mnt/testVol/tfile"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'setfattr -n trusted.overlay.opaque -v "y" /mnt/testVol/tfile'
	[ "$status" -eq 1 ]

	docker_stop $syscont
	docker volume rm testVol
}

@test "syscont-mode=false: env-var invalid" {

	run __docker run --rm -e "SYSBOX_SYSCONT_MODE=BAD_VAL" ${CTR_IMG_REPO}/alpine:latest echo "test"
	[ "$status" -ne 0 ]

	run __docker run --rm -e "SYSBOX_SYSCONT_MODE=BAD_VAL=BAD_VAL2" ${CTR_IMG_REPO}/alpine:latest echo "test"
	[ "$status" -ne 0 ]

	run __docker run --rm -e "SYSBOX_SYSCONT_MODE=" ${CTR_IMG_REPO}/alpine:latest echo "test"
	[ "$status" -ne 0 ]
}

@test "honor caps global config" {

	sysbox_stop
   sysbox_start --syscont-mode=false

	local syscont=$(docker_run --runtime=sysbox-runc --rm ${CTR_IMG_REPO}/alpine tail -f /dev/null)

	# Verify process caps are honored (same as --honor-caps)

	local docker_ver=$(docker_engine_version)
	local expectedCapInh="00000000a80425fb"
	if semver_ge $docker_ver "20.10.14"; then
		expectedCapInh="0000000000000000"
	fi

	docker exec "$syscont" sh -c "cat /proc/1/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"$expectedCapInh" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	# Verify read-only mounts: normally sysbox mounts these "rw", but should be
	# "ro" when SYSBOX_SYSCONT_MODE=false.

	docker exec "$syscont" sh -c 'mount | grep "sysboxfs on /proc/sys type fuse (ro"'
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c 'mount | grep "sysfs on /sys type sysfs (ro"'
	[ "$status" -eq 0 ]

	if host_is_cgroup_v2; then
		docker exec "$syscont" sh -c 'mount | grep "cgroup on /sys/fs/cgroup type cgroup2 (ro"'
		[ "$status" -eq 0 ]
	else
		docker exec "$syscont" sh -c 'mount | grep "/sys/fs/cgroup/"'
		[ "$status" -eq 0 ]
		for line in "${lines[@]}"; do
			echo "$line" | grep "ro,"
		done
	fi

	docker_stop $syscont

	local root_caps=$(get_root_capabilities)

	# Verify global config can be overriden by per-container config
	run __docker run --runtime=sysbox-runc \
		 -e "SYSBOX_SYSCONT_MODE=TRUE" \
		 --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"

	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"$root_caps" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"$root_caps" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"$root_caps" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"$root_caps" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"$root_caps" ]]

	sysbox_stop
	sysbox_start
}

@test "syscont-mode=false: nginx" {

	# Verify an nginx microservice works in a container with SYSBOX_SYSCONT_MODE=FALSE

	# this html file will be passed to the nginx container via a bind-mount
	#
	# Note that we place it in /root which has 700 permissions; this is
	# a requirement imposed by sysbox when using uid-shifting: the bind
	# source must be within a path searchable by true root only.

	tmpdir="/root/nginx"
	mkdir -p ${tmpdir}

	cat << EOF > ${tmpdir}/index.html
<html>
<header><title>test</title></header>
<body>
Nginx Test!
</body>
</html>
EOF

	# launch the sys container; bind-mount the index.html into it
	local syscont=$(docker_run --rm \
										-e SYSBOX_SYSCONT_MODE=FALSE \
										-v ${tmpdir}:/usr/share/nginx/html \
										-p 8080:80 \
										${CTR_IMG_REPO}/nginx:latest)

	wait_for_status_up

	# Temporary workaround for Linux kernel bug on sendfile()
	# See:
	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=f8ad8187c3b536ee2b10502a8340c014204a1af0
	# https://github.com/lxc/lxd/issues/8383

	docker exec $syscont sh -c 'sed -i -e "s/sendfile\s*on/sendfile off/" /etc/nginx/nginx.conf'
	[ "$status" -eq 0 ]

	docker exec $syscont sh -c 'nginx -s reload'
	[ "$status" -eq 0 ]

	sleep 2

	# verify the nginx container is up and running
	run wget -O ${tmpdir}/result.html http://localhost:8080
	[ "$status" -eq 0 ]

	run grep Nginx ${tmpdir}/result.html
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Nginx Test!" ]]

	docker_stop "$syscont"
	[ "$status" -eq 0 ]

	rm -rf ${tmpdir}
}

@test "syscont-mode=false: apache" {

	# Verify an apache microservice works in a container with SYSBOX_SYSCONT_MODE=FALSE

	# this html file will be passed to the apache container
	cat << EOF > /mnt/scratch/index.html
<html>
<header><title>test</title></header>
<body>
Apache Test!
</body>
</html>
EOF

	local syscont=$(docker_run --rm -e SYSBOX_SYSCONT_MODE=FALSE \
										-v /mnt/scratch/index.html:/usr/local/apache2/htdocs/index.html \
										-p 8080:80 \
										ghcr.io/nestybox/httpd-alpine)

	wait_for_status_up

	run wget http://localhost:8080 -O /root/index.html
	[ "$status" -eq 0 ]

	run grep Apache /root/index.html
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Apache Test!" ]]

	docker_stop "$syscont"
	[ "$status" -eq 0 ]

	rm /mnt/scratch/index.html
	rm /root/index.html
}

@test "syscont-mode=false: prometheus" {

	# Verify a prometheus microservice works in a container with SYSBOX_SYSCONT_MODE=FALSE

	cat > /mnt/scratch/prometheus.yml <<EOF
# scrape config for the Prometheus server itself
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 2s
    static_configs:
      - targets: ['localhost:9090']
EOF

	local syscont=$(docker_run --rm -e SYSBOX_SYSCONT_MODE=FALSE \
										-v /mnt/scratch/prometheus.yml:/etc/prometheus/prometheus.yml \
										-p 9090:9090 \
										ghcr.io/nestybox/prometheus)

	wait_for_status_up
	sleep 10

	run curl -s http://localhost:9090/api/v1/targets
	[ "$status" -eq 0 ]
	[[ "$output" =~ '"job":"prometheus"'.+'"health":"up"' ]]

	docker_stop "$syscont"
	rm /mnt/scratch/prometheus.yml
}
