#!/bin/bash

#
# mount helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

. $(dirname ${BASH_SOURCE[0]})/run.bash
. $(dirname ${BASH_SOURCE[0]})/sysbox-cfg.bash

function allow_immutable_remounts() {
	local options

	sysbox_get_cmdline_flags "sysbox-fs" options

	for param in "${options[@]}"; do
		if [[ ${param} == "--allow-immutable-remounts=true" ]] ||
			[[ ${param} == "--allow-immutable-remounts=\"true\"" ]]; then
			return 0
		fi
	done

	return 1
}

function allow_immutable_unmounts() {
	local options

	sysbox_get_cmdline_flags "sysbox-fs" options

	for param in "${options[@]}"; do
		if [[ ${param} == "--allow-immutable-unmounts=false" ]] ||
			[[ ${param} == "--allow-immutable-unmounts=\"false\"" ]]; then
			return 1
		fi
	done

	return 0
}

function is_list_empty() {
  local list=$1

  if [ -z ${list} ]; then
    return 0
  fi

  local elems=$(echo ${list} | tr " " "\n" | wc -l)
  if [[ ${elems} -eq 0 ]]; then
    return 0
  fi

  return 1
}

function list_container_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} mount | awk '{print \$3}' | grep -w -v \"/\""
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a mount | awk '{print \$3}' | grep -w -v \"/\""
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} mount | awk '{print \$3}' | grep -w -v \"/\""
  else
    __docker exec "$sc" sh -c "mount | awk '{print \$3}' | grep -w -v \"/\""
  fi
}

function list_container_ro_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} mount | grep \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a mount | grep \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} mount | grep \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  else
    __docker exec "$sc" sh -c \
      "mount | grep \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  fi
}

function list_container_rw_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} mount | grep -v \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a mount | grep -v \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} mount | grep -v \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  else
    __docker exec "$sc" sh -c \
      "mount | grep -v \"ro,\" | awk '{print \$3}' | grep -w -v \"/\""
  fi
}

# Note that 'chroot' if-statements are not properly working and need tweaking.
function list_container_file_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -f \$i; then echo \$i; fi; done"
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -f \$i; then echo \$i; fi; done"
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -f \$i; then echo \$i; fi; done"
  else
    __docker exec "$sc" sh -c \
      "list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -f \$i; then echo \$i; fi; done"
  fi
}

# Note that 'chroot' if-statements are not properly working and need tweaking.
function list_container_dir_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
     __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  else
    __docker exec "$sc" sh -c \
      "list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  fi
}

# Note that 'chroot' if-statements are not properly working and need tweaking.
function list_container_char_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -c \$i; then echo \$i; fi; done"
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -c \$i; then echo \$i; fi; done"
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -c \$i; then echo \$i; fi; done"
  else
    __docker exec "$sc" sh -c \
      "list=\$(mount | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -c \$i; then echo \$i; fi; done"
  fi
}

# Note that 'chroot' if-statements are not properly working and need tweaking.
function list_container_ro_dir_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} list=\$(mount | grep -v \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a list=\$(mount | grep -v \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} list=\$(mount | grep -v \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  else
    __docker exec "$sc" sh -c \
      "list=\$(mount | grep -v \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  fi
}

# Note that 'chroot' if-statements are not properly working and need tweaking.
function list_container_rw_dir_mounts() {
  local sc=$1
  local pid=$2
  local chrootpath=$3

  if [[ ${pid} != "0" ]] && [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a chroot ${chrootpath} list=\$(mount | grep \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  elif [[ ${pid} != "0" ]]; then
    __docker exec "$sc" sh -c \
      "nsenter -t ${pid} -a list=\$(mount | grep \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  elif [[ ${chrootpath} != "/" ]]; then
    __docker exec "$sc" sh -c \
      "chroot ${chrootpath} list=\$(mount | grep \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  else
    __docker exec "$sc" sh -c \
      "list=\$(mount | grep \"rw,\" | awk '{print \$3}' | grep -w -v \"/\"); for i in \$list; do if test -d \$i; then echo \$i; fi; done"
  fi
}

function chroot_prepare() {
  local sc=$1
  local rootfs=$2

  __docker exec "$sc" sh -c \
    "mkdir -p ${rootfs}/bin; \
    mkdir -p ${rootfs}/lib; \
    mkdir -p ${rootfs}/lib64; \

    \# Copy required binaries into the chroot path.
    cp /bin/awk ${rootfs}/bin; \
    cp /bin/bash ${rootfs}/bin; \
    cp /bin/cat ${rootfs}/bin; \
    cp /bin/mkdir ${rootfs}/bin; \
    cp /bin/mount ${rootfs}/bin; \
    cp /bin/umount ${rootfs}/bin; \
    cp /bin/rm ${rootfs}/bin; \
    cp /bin/touch ${rootfs}/bin; \

    \# Obtain the dependency list of each of the required binaries.
    awk_deps=\$(ldd /bin/awk | egrep -o '/lib.*\.[0-9]'); \
    awk_deps=\$(ldd /bin/awk | egrep -o '/lib.*\.[0-9]'); \
    bash_deps=\$(ldd /bin/bash | egrep -o '/lib.*\.[0-9]'); \
    cat_deps=\$(ldd /bin/cat | egrep -o '/lib.*\.[0-9]'); \
    mkdir_deps=\$(ldd /bin/mkdir | egrep -o '/lib.*\.[0-9]'); \
    mount_deps=\$(ldd /bin/mount | egrep -o '/lib.*\.[0-9]'); \
    umount_deps=\$(ldd /bin/umount | egrep -o '/lib.*\.[0-9]'); \
    rm_deps=\$(ldd /bin/rm | egrep -o '/lib.*\.[0-9]'); \
    touch_deps=\$(ldd /bin/touch | egrep -o '/lib.*\.[0-9]'); \

    \# Copy each binary dependency to the chroot path.
    for i in \${awk_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${bash_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${cat_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${mkdir_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${mount_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${umount_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${rm_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${touch_deps}; do cp --parents \${i} \"${rootfs}\"; done; \

    \# Launch chroot jail.
    chroot \"${rootfs}\" /bin/bash -c \"mkdir -p /proc && mount -t proc proc /proc\""
}

function chroot_prepare_nsenter() {
  local sc=$1
  local pid=$2
  local rootfs=$3

  __docker exec "$sc" nsenter -t ${pid} -a sh -c \
    "mkdir -p ${rootfs}/bin; \
    mkdir -p ${rootfs}/lib; \
    mkdir -p ${rootfs}/lib64; \

    \# Copy required binaries into the chroot path.
    cp /bin/awk ${rootfs}/bin; \
    cp /bin/bash ${rootfs}/bin; \
    cp /bin/cat ${rootfs}/bin; \
    cp /bin/mkdir ${rootfs}/bin; \
    cp /bin/mount ${rootfs}/bin; \
    cp /bin/umount ${rootfs}/bin; \
    cp /bin/rm ${rootfs}/bin; \
    cp /bin/touch ${rootfs}/bin; \

    \# Obtain the dependency list of each of the required binaries.
    awk_deps=\$(ldd /bin/awk | egrep -o '/lib.*\.[0-9]'); \
    awk_deps=\$(ldd /bin/awk | egrep -o '/lib.*\.[0-9]'); \
    bash_deps=\$(ldd /bin/bash | egrep -o '/lib.*\.[0-9]'); \
    cat_deps=\$(ldd /bin/cat | egrep -o '/lib.*\.[0-9]'); \
    mkdir_deps=\$(ldd /bin/mkdir | egrep -o '/lib.*\.[0-9]'); \
    mount_deps=\$(ldd /bin/mount | egrep -o '/lib.*\.[0-9]'); \
    umount_deps=\$(ldd /bin/umount | egrep -o '/lib.*\.[0-9]'); \
    rm_deps=\$(ldd /bin/rm | egrep -o '/lib.*\.[0-9]'); \
    touch_deps=\$(ldd /bin/touch | egrep -o '/lib.*\.[0-9]'); \

    \# Copy each binary dependency to the chroot path.
    for i in \${awk_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${bash_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${cat_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${mkdir_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${mount_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${umount_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${rm_deps}; do cp --parents \${i} \"${rootfs}\"; done; \
    for i in \${touch_deps}; do cp --parents \${i} \"${rootfs}\"; done; \

    \# Launch chroot jail.
    chroot \"${rootfs}\" /bin/bash -c \"mkdir -p /proc && mount -t proc proc /proc\""
}
