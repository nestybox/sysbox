#
# Sysbox Makefile
#

.PHONY: sysbox sysbox-debug sysbox-static \
	sysbox-local sysbox-debug-local sysbox-static-local \
	sysbox-runc sysbox-runc-static sysbox-runc-debug \
	sysbox-fs sysbox-fs-static sysbox-fs-debug \
	sysbox-mgr sysbox-mgr-static sysbox-mgr-debug \
	sysbox-ipc \
	install uninstall \
	test \
	test-sysbox test-sysbox-ci test-sysbox-systemd test-sysbox-installer \
	test-sysbox-shiftuid test-sysbox-shiftuid-ci test-sysbox-shiftuid-systemd test-sysbox-shiftuid-installer \
	test-runc test-fs test-mgr \
	test-shell test-shell-debug test-shell-systemd test-shell-systemd-debug test-shell-installer test-shell-installer-debug \
	test-shell-shiftuid test-shell-shiftuid-debug test-shell-shiftuid-systemd test-shell-shiftuid-systemd-debug test-shell-shiftuid-installer test-shell-shiftuid-installer-debug \
	test-img test-img-systemd test-cleanup \
	test-sysbox-local test-sysbox-local-installer test-sysbox-local-ci test-fs-local test-mgr-local \
	sysbox-in-docker sysbox-in-docker-local \
	test-sind test-sind-local test-sind-shell \
	lint lint-local lint-sysbox-local lint-tests-local shfmt \
	sysbox-runc-recvtty \
	listRuncPkgs listFsPkgs listMgrPkgs \
	clean

export SHELL=bash

ifeq ($(HOSTNAME),)
	export HOSTNAME=$(shell hostname)
endif

export VERSION := $(shell cat ./VERSION)
export EDITION := Community Edition (CE)
export PACKAGE := sysbox-ce
export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)

# Obtain the current system architecture.
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
	SYS_ARCH := amd64
else ifeq ($(UNAME_M),aarch64)
	SYS_ARCH := arm64
else ifeq ($(UNAME_M),arm)
	SYS_ARCH := armhf
else ifeq ($(UNAME_M),armel)
	SYS_ARCH := armel
endif

# Set target architecture if not explicitly defined by user.
ifeq ($(TARGET_ARCH),)
	TARGET_ARCH := $(SYS_ARCH)
endif

# Compute the target triple.
ifeq ($(TARGET_ARCH),armel)
	HOST_TRIPLE := arm-linux-gnueabi
else ifeq ($(TARGET_ARCH),armhf)
	HOST_TRIPLE := arm-linux-gnueabihf
else ifeq ($(TARGET_ARCH),arm64)
	HOST_TRIPLE := aarch64-linux-gnu
else
	HOST_TRIPLE := x86_64-linux-gnu
endif

export SYS_ARCH
export TARGET_ARCH
export HOST_TRIPPLE

# Source-code paths of the sysbox binary targets.
SYSRUNC_DIR     := sysbox-runc
SYSFS_DIR       := sysbox-fs
SYSMGR_DIR      := sysbox-mgr
SYSIPC_DIR      := sysbox-ipc
SYSLIBS_DIR     := sysbox-libs
LIB_SECCOMP_DIR := $(SYSLIBS_DIR)/libseccomp-golang
SYSBOX_IN_DOCKER_DIR := sysbox-in-docker

# Consider to have this one moved out within sysbox-runc folder.
SYSRUNC_BUILDTAGS := seccomp apparmor

PROJECT := /root/nestybox/sysbox

# Sysbox binary targets destination.
ifeq ($(DESTDIR),)
INSTALL_DIR := /usr/bin
else
INSTALL_DIR := ${DESTDIR}
endif

IMAGE_BASE_DISTRO := $(shell lsb_release -is | tr '[:upper:]' '[:lower:]')

# Host kernel info
KERNEL_REL := $(shell uname -r)
export KERNEL_REL

# Sysbox image-generation globals utilized during the sysbox's building and testing process.
ifeq ($(IMAGE_BASE_DISTRO),$(filter $(IMAGE_BASE_DISTRO),centos fedora redhat))
	IMAGE_BASE_RELEASE := $(shell lsb_release -ds | tr -dc '0-9.' | cut -d'.' -f1)
	KERNEL_HEADERS := kernels/$(KERNEL_REL)
else
	IMAGE_BASE_RELEASE := $(shell lsb_release -cs)
	ifeq ($(IMAGE_BASE_DISTRO),linuxmint)
		IMAGE_BASE_DISTRO := ubuntu
		ifeq ($(IMAGE_BASE_RELEASE),$(filter $(IMAGE_BASE_RELEASE),ulyana ulyssa uma))
			IMAGE_BASE_RELEASE := focal
		endif
		ifeq ($(IMAGE_BASE_RELEASE),$(filter $(IMAGE_BASE_RELEASE),tara tessa tina tricia))
			IMAGE_BASE_RELEASE := bionic
		endif
	endif
	KERNEL_HEADERS := linux-headers-$(KERNEL_REL)
	KERNEL_HEADERS_BASE := $(shell find /usr/src/$(KERNEL_HEADERS) -maxdepth 1 -type l -exec readlink {} \; | cut -d"/" -f2 | egrep -v "^\.\." | head -1)
endif

TEST_DIR := $(CURDIR)/tests
TEST_IMAGE := sysbox-test-$(TARGET_ARCH)
TEST_IMAGE_FLATCAR := sysbox-test-flatcar-$(TARGET_ARCH):$(FLATCAR_VERSION)

TEST_SYSTEMD_IMAGE := sysbox-systemd-test
TEST_SYSTEMD_DOCKERFILE := Dockerfile.systemd.$(IMAGE_BASE_DISTRO)

TEST_FILES := $(shell find tests -type f | egrep "\.bats")
TEST_SCR := $(shell grep -rwl -e '\#!/bin/bash' -e '\#!/bin/sh' tests/*)

ifeq ($(KERNEL_HEADERS_BASE), )
	KERNEL_HEADERS_MOUNTS := -v /usr/src/$(KERNEL_HEADERS):/usr/src/$(KERNEL_HEADERS):ro
else
	KERNEL_HEADERS_MOUNTS := -v /usr/src/$(KERNEL_HEADERS):/usr/src/$(KERNEL_HEADERS):ro \
				 -v /usr/src/$(KERNEL_HEADERS_BASE):/usr/src/$(KERNEL_HEADERS_BASE):ro
endif

export KERNEL_HEADERS
export KERNEL_HEADERS_MOUNTS

PACKAGE_FILE_PATH ?= sysbox-pkgr/deb/debbuild/$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE)
PACKAGE_FILE_NAME := $(PACKAGE)_$(VERSION)-0.$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE)_amd64.deb

# Volumes to mount into the privileged test container. These are
# required because certain mounts inside the test container can't
# be backed by overlayfs (e.g., /var/lib/docker, /var/lib/sysbox, etc.).
# Note that the volumes must not be on tmpfs either, because the
# docker engine inside the privileged test container will mount overlayfs
# on top , and overlayfs can't be mounted on top of tmpfs.
TEST_VOL1 := /var/tmp/sysbox-test-var-lib
TEST_VOL2 := /var/tmp/sysbox-test-scratch
TEST_VOL3 := /var/tmp/sysbox-test-var-run

export TEST_VOL1
export TEST_VOL2
export TEST_VOL3

# In scenarios where the egress-interface's mtu is lower than expected (1500 bytes),
# we must explicitly configure dockerd with such a value.
EGRESS_IFACE := $(shell ip route show | awk '/default via/ {print $$5}')
EGRESS_IFACE_MTU := $(shell ip link show dev $(EGRESS_IFACE) | awk '/mtu/ {print $$5}')

# Find out if the host supports uid shifting.
#
# NOTE: for now uid shifting necessarily means the presence of the shiftfs kernel module.
# In the near future, we expect this will be replaced with kernel ID-mapped mounts.
HOST_SUPPORTS_UID_SHIFT := $(shell modprobe shiftfs >/dev/null 2>&1 && lsmod | grep shiftfs)

# libseccomp (used by Sysbox components)
LIBSECCOMP := sysbox-libs/libseccomp/src/.libs/libseccomp.a
LIBSECCOMP_DIR := sysbox-libs/libseccomp
LIBSECCOMP_SRC := $(shell find $(LIBSECCOMP_DIR)/src 2>&1 | grep -E '.*\.(c|h)')
LIBSECCOMP_SRC += $(shell find $(LIBSECCOMP_DIR)/include 2>&1 | grep -E '.*\.h')

# Ensure that a gitconfig file is always present.
$(shell touch $(HOME)/.gitconfig)

#
# build targets
# TODO: parallelize building of runc, fs, and mgr; note that grpc must be built before these.
#

.DEFAULT := help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-40s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Building targets

DOCKER_SYSBOX_BLD := docker run --privileged --rm --runtime=runc      \
			--hostname sysbox-build                       \
			--name sysbox-build                           \
			-e SYS_ARCH=$(SYS_ARCH)                       \
			-e TARGET_ARCH=$(TARGET_ARCH)                 \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v $(HOME)/.gitconfig:/root/.gitconfig        \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			$(KERNEL_HEADERS_MOUNTS) \
			$(TEST_IMAGE)

DOCKER_SYSBOX_BLD_FLATCAR := docker run --privileged --rm --runtime=runc      \
			--hostname sysbox-build                       \
			--name sysbox-build                           \
			-e ARCH=$(ARCH)                               \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v $(HOME)/.gitconfig:/root/.gitconfig        \
			$(TEST_IMAGE_FLATCAR)

sysbox: ## Build sysbox (the build occurs inside a container, so the host is not polluted)
sysbox: test-img
	@printf "\n** Building sysbox (target-arch: $(TARGET_ARCH)) **\n\n"
	$(DOCKER_SYSBOX_BLD) /bin/bash -c "export HOST_UID=$(HOST_UID) && \
		export HOST_GID=$(HOST_GID) && buildContainerInit sysbox-local"

sysbox-flatcar: test-img-flatcar
	@printf "\n** Building sysbox for Kinvolk's Flatcar OS (target-arch: $(TARGET_ARCH)) **\n\n"
	$(DOCKER_SYSBOX_BLD_FLATCAR) /bin/bash -c "export HOST_UID=$(HOST_UID) && \
		export HOST_GID=$(HOST_GID) && buildContainerInit sysbox-local"

sysbox-debug: ## Build sysbox (with debug symbols)
sysbox-debug: test-img
	@printf "\n** Building sysbox with debuging on (target-arch: $(TARGET_ARCH)) **\n\n"
	$(DOCKER_SYSBOX_BLD) /bin/bash -c "export HOST_UID=$(HOST_UID) && \
		export HOST_GID=$(HOST_GID) && buildContainerInit sysbox-debug-local"

sysbox-static: ## Build sysbox (static linking)
sysbox-static: test-img
	@printf "\n** Building sysbox statically (target-arch: $(TARGET_ARCH)) **\n\n"
	$(DOCKER_SYSBOX_BLD) /bin/bash -c "export HOST_UID=$(HOST_UID) && \
		export HOST_GID=$(HOST_GID) && buildContainerInit sysbox-static-local"

sysbox-local: sysbox-runc sysbox-fs sysbox-mgr
	@echo $(HOSTNAME)-$(TARGET_ARCH) > .buildinfo

sysbox-debug-local: sysbox-runc-debug sysbox-fs-debug sysbox-mgr-debug

sysbox-static-local: sysbox-runc-static sysbox-fs-static sysbox-mgr-static

sysbox-runc: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)"

sysbox-runc-debug: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" sysbox-runc-debug

sysbox-runc-static: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSRUNC_DIR) && make static

sysbox-fs: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSFS_DIR) && make

sysbox-fs-debug: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSFS_DIR) && make sysbox-fs-debug

sysbox-fs-static: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSFS_DIR) && make sysbox-fs-static

sysbox-mgr: sysbox-ipc
	@cd $(SYSMGR_DIR) && make

sysbox-mgr-debug: sysbox-ipc
	@cd $(SYSMGR_DIR) && make sysbox-mgr-debug

sysbox-mgr-static: sysbox-ipc
	@cd $(SYSMGR_DIR) && make sysbox-mgr-static

sysbox-ipc:
	@cd $(SYSIPC_DIR) && make sysbox-ipc

$(LIBSECCOMP): $(LIBSECCOMP_SRC)
	@echo "Building libseccomp ..."
	@cd $(LIBSECCOMP_DIR) && ./autogen.sh && ./configure --host $(HOST_TRIPLE) && make
	@chown -R $(HOST_UID):$(HOST_GID) ./sysbox-libs/libseccomp
	@echo "Building libseccomp completed."

#
# install targets (require root privileges)
#

##@ Installation targets

install: ## Install all sysbox binaries (requires root privileges)
	install -D -m0755 sysbox-fs/build/$(TARGET_ARCH)/sysbox-fs $(INSTALL_DIR)/sysbox-fs
	install -D -m0755 sysbox-mgr/build/$(TARGET_ARCH)/sysbox-mgr $(INSTALL_DIR)/sysbox-mgr
	install -D -m0755 sysbox-runc/build/$(TARGET_ARCH)/sysbox-runc $(INSTALL_DIR)/sysbox-runc
	install -D -m0755 scr/sysbox $(INSTALL_DIR)/sysbox

uninstall: ## Uninstall all sysbox binaries (requires root privileges)
	rm -f $(INSTALL_DIR)/sysbox
	rm -f $(INSTALL_DIR)/sysbox-fs
	rm -f $(INSTALL_DIR)/sysbox-mgr
	rm -f $(INSTALL_DIR)/sysbox-runc

#
# Test targets
#
# These targets run Sysbox tests within a privileged test container.
# they are meant as development tests.
#

# For batch targets
DOCKER_RUN := docker run --privileged --rm --runtime=runc         \
			--hostname sysbox-test                        \
			--name sysbox-test                            \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(TEST_VOL1):/var/lib                      \
			-v $(TEST_VOL2):/mnt/scratch                  \
			-v $(TEST_VOL3):/var/run                      \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			-v $(HOME)/.gitconfig:/root/.gitconfig        \
			$(KERNEL_HEADERS_MOUNTS) \
			$(TEST_IMAGE)

# For interactive targets
DOCKER_RUN_TTY := docker run -it --privileged --rm --runtime=runc         \
			--hostname sysbox-test                        \
			--name sysbox-test                            \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(TEST_VOL1):/var/lib                      \
			-v $(TEST_VOL2):/mnt/scratch                  \
			-v $(TEST_VOL3):/var/run                      \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			-v $(HOME)/.gitconfig:/root/.gitconfig        \
			$(KERNEL_HEADERS_MOUNTS) \
			$(TEST_IMAGE)

# Must use "--cgroups private" as otherwise the inner Docker may get confused
# when configured with the systemd cgroup driver.
DOCKER_RUN_SYSTEMD := docker run -d --rm --runtime=runc --privileged  \
			--hostname sysbox-test                        \
			--name sysbox-test                            \
			--cgroupns private                            \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(TEST_VOL1):/var/lib                      \
			-v $(TEST_VOL2):/mnt/scratch                  \
			-v $(TEST_VOL3):/var/run                      \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules:/lib/modules:ro               \
			-v $(HOME)/.gitconfig:/root/.gitconfig        \
			$(KERNEL_HEADERS_MOUNTS)                      \
			--mount type=tmpfs,destination=/run           \
			--mount type=tmpfs,destination=/run/lock      \
			$(TEST_SYSTEMD_IMAGE)

DOCKER_EXEC := docker exec -it sysbox-test
DOCKER_STOP := docker stop -t0 sysbox-test

##@ Testing targets

test: ## Run all sysbox test suites
test: test-fs test-mgr test-runc test-sysbox test-sysbox-shiftuid test-sysbox-systemd

test-sysbox: ## Run sysbox integration tests
test-sysbox: test-prereq test-img
	@printf "\n** Running sysbox integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"

test-sysbox-ci: ## Run sysbox integration tests (continuous integration)
test-sysbox-ci: test-prereq test-img test-fs test-mgr
	@printf "\n** Running sysbox integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && make test-sysbox-local-ci TESTPATH=$(TESTPATH)"

test-sysbox-systemd: ## Run sysbox integration tests in a test container with systemd
test-sysbox-systemd: test-prereq test-img-systemd
	@printf "\n** Running sysbox integration tests (with systemd) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP)

test-sysbox-installer: ## Run sysbox integration tests in a test container with systemd and the sysbox installer
test-sysbox-installer: test-prereq test-img-systemd
	@printf "\n** Running sysbox integration tests (with systemd + the sysbox installer) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SB_INSTALLER=true SB_PACKAGE=$(PACKAGE) SB_PACKAGE_FILE=$(PACKAGE_FILE_PATH)/$(PACKAGE_FILE_NAME) && \
		testContainerInit && \
		make test-sysbox-local TESTPATH=$(TESTPATH) && \
		make test-sysbox-local-installer TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP)

test-sysbox-shiftuid: ## Run sysbox integration tests with uid-shifting (shiftfs)
test-sysbox-shiftuid: test-prereq test-img
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_ROOTFS_UIDS=true && testContainerInit && \
		make test-sysbox-local TESTPATH=$(TESTPATH)"
endif

test-sysbox-shiftuid-ci: ## Run sysbox integration tests with uid-shifting (shiftfs) (continuous integration)
test-sysbox-shiftuid-ci: test-prereq test-img test-fs test-mgr
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_ROOTFS_UIDS=true && testContainerInit && \
		make test-sysbox-local-ci TESTPATH=$(TESTPATH)"
endif

test-sysbox-shiftuid-systemd: ## Run sysbox integration tests with uid-shifting (shiftfs) and systemd
test-sysbox-shiftuid-systemd: test-prereq test-img-systemd
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting and systemd) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_ROOTFS_UIDS=true && testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP)
endif

test-sysbox-shiftuid-installer: ## Run sysbox integration tests in a test with uid-shifting (shiftfs), systemd, and the sysbox installer
test-sysbox-shiftuid-installer: test-prereq test-img-systemd
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting + systemd + the sysbox installer) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_ROOTFS_UIDS=true SB_INSTALLER=true SB_PACKAGE=$(PACKAGE) SB_PACKAGE_FILE=$(PACKAGE_FILE_PATH)/$(PACKAGE_FILE_NAME) && \
		testContainerInit && \
		make test-sysbox-local TESTPATH=$(TESTPATH) && \
		make test-sysbox-local-installer TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP)
endif

test-runc: ## Run sysbox-runc unit & integration tests
test-runc: test-prereq sysbox
	@printf "\n** Running sysbox-runc unit & integration tests **\n\n"
	cd $(SYSRUNC_DIR) && make clean && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" test

test-fs: ## Run sysbox-fs unit tests
test-fs: test-prereq sysbox
	@printf "\n** Running sysbox-fs unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-fs-local"

test-mgr: ## Run sysbox-mgr unit tests
test-mgr: test-prereq test-img
	@printf "\n** Running sysbox-mgr unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-mgr-local"

test-shell: ## Get a shell in the test container (useful for debug)
test-shell: test-prereq test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_TTY) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		make sysbox-runc-recvtty && \
		testContainerInit && /bin/bash"

test-shell-debug: test-prereq test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_TTY) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		make sysbox-runc-recvtty && \
		export DEBUG_ON=true && testContainerInit && /bin/bash"

test-shell-systemd: ## Get a shell in the test container that includes systemd (useful for debug)
test-shell-systemd: test-prereq test-img-systemd
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU))
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)

test-shell-systemd-debug: test-img-systemd
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) -e DEBUG_ON=true)
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)

test-shell-installer: ## Get a shell in the test container that includes systemd and the sysbox installer (useful for debug)
test-shell-installer: test-prereq test-img-systemd
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) \
		-e SB_INSTALLER=true -e SB_PACKAGE=$(PACKAGE) \
		-e SB_PACKAGE_FILE=$(PACKAGE_FILE_PATH)/$(PACKAGE_FILE_NAME))
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)

test-shell-installer-debug: test-prereq test-img-systemd
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) \
		-e SB_INSTALLER=true -e SB_PACKAGE=$(PACKAGE) \
		-e SB_PACKAGE_FILE=$(PACKAGE_FILE_PATH)/$(PACKAGE_FILE_NAME) \
		-e DEBUG_ON=true)
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)

test-shell-shiftuid: ## Get a shell in the test container with uid-shifting
test-shell-shiftuid: test-prereq test-img
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_TTY) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		make sysbox-runc-recvtty && \
		export SHIFT_ROOTFS_UIDS=true && testContainerInit && /bin/bash"
endif

test-shell-shiftuid-debug: test-prereq test-img
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_TTY) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		make sysbox-runc-recvtty && \
		export SHIFT_ROOTFS_UIDS=true DEBUG_ON=true && testContainerInit && /bin/bash"
endif

test-shell-shiftuid-systemd: ## Get a shell in the test container that includes shiftfs & systemd (useful for debug)
test-shell-shiftuid-systemd: test-prereq test-img-systemd
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) -e SHIFT_ROOTFS_UIDS=true)
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)
endif

test-shell-shiftuid-systemd-debug: test-prereq test-img-systemd
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) -e SHIFT_ROOTFS_UIDS=true -e DEBUG_ON=true)
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)
endif

test-shell-shiftuid-installer: ## Get a shell in the test container that includes shiftfs, systemd and the sysbox installer (useful for debug)
test-shell-shiftuid-installer: test-prereq test-img-systemd
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) -e SHIFT_ROOTFS_UIDS=true \
		-e SB_INSTALLER=true -e SB_PACKAGE=$(PACKAGE) \
		-e SB_PACKAGE_FILE-$(PACKAGE_FILE_PATH)/$(PACKAGE_FILE_NAME))
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)
endif

test-shell-shiftuid-installer-debug: test-prereq test-img-systemd
ifeq ($(HOST_SUPPORTS_UID_SHIFT), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	$(eval DOCKER_ENV := -e PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) -e SHIFT_ROOTFS_UIDS=true \
		-e SB_INSTALLER=true -e SB_PACKAGE=$(PACKAGE) \
		-e SB_PACKAGE_FILE=$(PACKAGE_FILE_PATH)/$(PACKAGE_FILE_NAME) \
		-e DEBUG_ON=true)
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec $(DOCKER_ENV) sysbox-test make sysbox-runc-recvtty
	docker exec $(DOCKER_ENV) sysbox-test testContainerInit
	docker exec -it $(DOCKER_ENV) sysbox-test /bin/bash
	$(DOCKER_STOP)
endif

test-prereq:
ifneq ($(SYS_ARCH),$(TARGET_ARCH))
	@printf "\n\n*** Test execution targets are not allowed in cross-compilation setups: sys-arch \"$(SYS_ARCH)\", target-arch \"$(TARGET_ARCH)\" ***\n\n"
	@exit 1
endif

test-img: ## Build test container image
test-img:
	@printf "\n** Building the test container **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_IMAGE) \
		--build-arg sys_arch=$(SYS_ARCH) --build-arg target_arch=$(TARGET_ARCH) \
		-f Dockerfile.$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE) .

test-img-systemd: ## Build test container image that includes systemd
test-img-systemd: test-img
	@printf "\n** Building the test container image (includes systemd) **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_SYSTEMD_IMAGE) \
		--build-arg sys_arch=$(SYS_ARCH) --build-arg target_arch=$(TARGET_ARCH) \
		-f $(TEST_SYSTEMD_DOCKERFILE) .

test-img-flatcar: ## Build test container image for Flatcar
test-img-flatcar:
	@printf "\n** Building the test container for Flatcar **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_IMAGE_FLATCAR) \
		--build-arg arch=$(SYS_ARCH) --build-arg target_arch=$(TARGET_ARCH) \
		--build-arg FLATCAR_VERSION=$(FLATCAR_VERSION) \
		-f Dockerfile.flatcar .

test-cleanup: ## Clean up sysbox integration tests (requires root privileges)
test-cleanup: test-img
	@printf "\n** Cleaning up sysbox integration tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "testContainerCleanup"
	$(TEST_DIR)/scr/testContainerPost $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)

#
# Local test targets (these are invoked from within the test container
# by the test target above); in theory they can run directly on a host
# machine, but they require root privileges and might messup the state
# of the host.
#

test-sysbox-local: sysbox-runc-recvtty
	$(TEST_DIR)/scr/testSysbox $(TESTPATH)

test-sysbox-local-installer: sysbox-runc-recvtty
	$(TEST_DIR)/scr/testSysboxInstaller $(TESTPATH)

test-sysbox-local-ci: sysbox-runc-recvtty
	$(TEST_DIR)/scr/testSysboxCI $(TESTPATH)

test-fs-local: sysbox-ipc
	cd $(SYSFS_DIR) && go test -timeout 3m -v $(fsPkgs)

test-mgr-local: sysbox-ipc
	dockerd > /var/log/dockerd.log 2>&1 &
	sleep 2
	cd $(SYSMGR_DIR) && go test -timeout 3m -v $(mgrPkgs)


##@ Sysbox-In-Docker targets

sysbox-in-docker: ## Build sysbox-in-docker sandbox image
sysbox-in-docker: sysbox
	@cp -f sysbox-mgr/build/$(TARGET_ARCH)/sysbox-mgr sysbox-in-docker/
	@cp -f sysbox-runc/build/$(TARGET_ARCH)/sysbox-runc sysbox-in-docker/
	@cp -f sysbox-fs/build/$(TARGET_ARCH)/sysbox-fs sysbox-in-docker/
	@make -C $(SYSBOX_IN_DOCKER_DIR) $(filter-out $@,$(MAKECMDGOALS))

sysbox-in-docker-local: sysbox-local
	@cp sysbox-mgr/build/$(TARGET_ARCH)/sysbox-mgr sysbox-in-docker/
	@cp sysbox-runc/build/$(TAGET_ARCH)/sysbox-runc sysbox-in-docker/
	@cp sysbox-fs/build/$(TAGET_ARCH)/sysbox-fs sysbox-in-docker/
	@make -C $(SYSBOX_IN_DOCKER_DIR) $(filter-out $@,$(MAKECMDGOALS))

test-sind: ## Run the sysbox-in-docker integration tests
test-sind: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		sindTestContainerInit && make test-sind-local"

test-sind-local:
	$(TEST_DIR)/scr/testSysboxInDocker $(TESTPATH)

test-sind-shell: ## Get a shell in the test container for sysbox-in-docker (useful for debug)
test-sind-shell: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_TTY) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		sindTestContainerInit && /bin/bash"

##@ Code Hygiene targets

lint: ## Runs lint checker on sysbox source code and tests
lint: test-img
	@printf "\n** Linting sysbox **\n\n"
	$(DOCKER_SYSBOX_BLD) /bin/bash -c "make lint-local"

lint-local: lint-sysbox-local lint-tests-local

lint-sysbox-local:
	@cd $(SYSRUNC_DIR) && make lint
	@cd $(SYSMGR_DIR) && make lint
	@cd $(SYSFS_DIR) && make lint
	@cd $(SYSIPC_DIR) && make lint
	@cd $(SYSLIBS_DIR) && make lint

lint-tests-local:
	shellcheck $(TEST_FILES)
	shellcheck $(TEST_SCR)

shfmt: ## Formats shell scripts in the repo; requires shfmt.
shfmt:
	shfmt -ln bats -d -w $(TEST_FILES)
	shfmt -ln bash -d -w $(TEST_SCR)

#
# Misc targets
#

# recvtty is a tool inside the sysbox-runc repo that is needed by some integration tests
sysbox-runc-recvtty:
	@cd $(SYSRUNC_DIR) && make recvtty

listRuncPkgs:
	@echo $(runcPkgs)

listFsPkgs:
	@echo $(fsPkgs)

listMgrPkgs:
	@echo $(mgrPkgs)

#
# cleanup targets
#

##@ Cleaning targets

clean: ## Eliminate sysbox binaries
clean: clean-libseccomp
	cd $(SYSRUNC_DIR) && make clean TARGET_ARCH=$(TARGET_ARCH)
	cd $(SYSFS_DIR) && make clean TARGET_ARCH=$(TARGET_ARCH)
	cd $(SYSMGR_DIR) && make clean TARGET_ARCH=$(TARGET_ARCH)
	cd $(SYSIPC_DIR) && make clean TARGET_ARCH=$(TARGET_ARCH)
	rm -rf ./build/$(TARGET_ARCH)


distclean: ## Eliminate all sysbox binaries
distclean: clean-libseccomp
	cd $(SYSRUNC_DIR) && make distclean
	cd $(SYSFS_DIR) && make distclean
	cd $(SYSMGR_DIR) && make distclean
	cd $(SYSIPC_DIR) && make distclean
	rm -rf ./build

clean-libseccomp: ## Clean libseccomp
clean-libseccomp:
	cd $(LIBSECCOMP_DIR) && ([ -f ./Makefile ] && make distclean || true)

clean-sysbox-in-docker: ## Clean sysbox-in-docker
clean-sysbox-in-docker:
	cd $(SYSBOX_IN_DOCKER_DIR) && rm -f sysbox-fs sysbox-runc sysbox-mgr

# memoize all packages once

_runcPkgs = $(shell cd $(SYSRUNC_DIR) && go list ./... | grep -v vendor)
runcPkgs = $(if $(__runcPkgs),,$(eval __runcPkgs := $$(_runcPkgs)))$(__runcPkgs)

_fsPkgs = $(shell cd $(SYSFS_DIR) && go list ./... | grep -v vendor)
fsPkgs = $(if $(__fsPkgs),,$(eval __fsPkgs := $$(_fsPkgs)))$(__fsPkgs)

_mgrPkgs = $(shell cd $(SYSMGR_DIR) && go list ./... | grep -v vendor)
mgrPkgs = $(if $(__mgrPkgs),,$(eval __mgrPkgs := $$(_mgrPkgs)))$(__mgrPkgs)
