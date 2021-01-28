#
# Sysbox Makefile
#

.PHONY: sysbox sysbox-static \
	sysbox-runc sysbox-runc-static sysbox-runc-debug \
	sysbox-fs sysbox-fs-static sysbox-fs-debug \
	sysbox-mgr sysbox-mgr-static sysbox-mgr-debug \
	sysbox-ipc \
	install uninstall \
	test \
	test-sysbox test-sysbox-ci test-sysbox-shiftuid test-sysbox-shiftuid-ci test-sysbox-local \
	test-runc test-fs test-mgr \
	test-shell test-shell-shiftuid \
	test-fs-local test-mgr-local \
	test-img test-cleanup \
	listRuncPkgs listFsPkgs listMgrPkgs \
	pjdfstest pjdfstest-clean \
	sysbox-in-docker sysbox-in-docker-local \
	test-sind-shell \
	centos-8 debian-buster debian-bullseye fedora-31 fedora-32 ubuntu-bionic ubuntu-focal ubuntu-eoan \
	lint lint-local lint-sysbox-local lint-tests-local shfmt
	clean

export SHELL=bash

ifeq ($(HOSTNAME),)
export HOSTNAME=$(shell hostname)
endif

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
INSTALL_DIR := /usr/local/sbin
else
INSTALL_DIR := ${DESTDIR}
endif

TEST_DIR := $(CURDIR)/tests
TEST_IMAGE := sysbox-test

TEST_SYSTEMD_IMAGE := sysbox-systemd-test
TEST_SYSTEMD_DOCKERFILE := Dockerfile.systemd

TEST_FILES := $(shell find tests -type f | egrep "\.bats")
TEST_SCR := $(shell grep -rwl -e '\#!/bin/bash' -e '\#!/bin/sh' tests/*)

# Host kernel info
KERNEL_REL := $(shell uname -r)
export KERNEL_REL

# Sysbox image-generation globals utilized during the sysbox's building and testing process.
IMAGE_BASE_DISTRO := $(shell lsb_release -is | tr '[:upper:]' '[:lower:]')
ifeq ($(IMAGE_BASE_DISTRO),$(filter $(IMAGE_BASE_DISTRO),centos fedora redhat))
	IMAGE_BASE_RELEASE := $(shell lsb_release -ds | tr -dc '0-9.' | cut -d'.' -f1)
	KERNEL_HEADERS := kernels/$(KERNEL_REL)
else
	IMAGE_BASE_RELEASE := $(shell lsb_release -cs)
	KERNEL_HEADERS := linux-headers-$(KERNEL_REL)
	KERNEL_HEADERS_BASE := $(shell find /usr/src/$(KERNEL_HEADERS) -maxdepth 1 -type l -exec readlink {} \; | cut -d"/" -f2 | egrep -v "^\.\." | head -1)
endif
ifeq ($(KERNEL_HEADERS_BASE), )
	KERNEL_HEADERS_MOUNTS := -v /usr/src/$(KERNEL_HEADERS):/usr/src/$(KERNEL_HEADERS):ro
else
	KERNEL_HEADERS_MOUNTS := -v /usr/src/$(KERNEL_HEADERS):/usr/src/$(KERNEL_HEADERS):ro \
				 -v /usr/src/$(KERNEL_HEADERS_BASE):/usr/src/$(KERNEL_HEADERS_BASE):ro
endif

export KERNEL_HEADERS
export KERNEL_HEADERS_MOUNTS

IMAGE_FILE_PATH := image/deb/debbuild/$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE)
IMAGE_FILE_NAME := sysbox_$(VERSION)-0.$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE)_amd64.deb

# Volumes to mount into the privileged test container. These are
# required because certain mounts inside the test container can't
# be backed by overlayfs (e.g., /var/lib/docker, /var/lib/sysbox, etc.).
# Note that the volumes must not be on tmpfs either, because the
# docker engine inside the privileged test container will mount overlayfs
# on top , and overlayfs can't be mounted on top of tmpfs.
TEST_VOL1 := /var/tmp/sysbox-test-var-lib-docker
TEST_VOL2 := /var/tmp/sysbox-test-var-lib-sysbox
TEST_VOL3 := /var/tmp/sysbox-test-scratch
export TEST_VOL1
export TEST_VOL2
export TEST_VOL3

# In scenarios where the egress-interface's mtu is lower than expected (1500 bytes),
# we must explicitly configure dockerd with such a value.
EGRESS_IFACE := $(shell ip route show | awk '/default via/ {print $$5}')
EGRESS_IFACE_MTU := $(shell ip link show dev $(EGRESS_IFACE) | awk '/mtu/ {print $$5}')

# Find out if 'shiftfs' module is present.
SHIFTUID_ON := $(shell modprobe shiftfs >/dev/null 2>&1 && lsmod | grep shiftfs)

# libseccomp (used by Sysbox components)
LIBSECCOMP := sysbox-libs/libseccomp/src/.libs/libseccomp.a
LIBSECCOMP_DIR := sysbox-libs/libseccomp
LIBSECCOMP_SRC := $(shell find $(LIBSECCOMP_DIR)/src 2>&1 | grep -E '.*\.(c|h)')
LIBSECCOMP_SRC += $(shell find $(LIBSECCOMP_DIR)/include 2>&1 | grep -E '.*\.h')

#
# build targets
# TODO: parallelize building of runc, fs, and mgr; note that grpc must be built before these.
#

.DEFAULT := help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Building targets

DOCKER_SYSBOX_BLD := docker run --privileged --rm --runtime=runc      \
			--hostname sysbox-build                       \
			--name sysbox-build                           \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			$(KERNEL_HEADERS_MOUNTS) \
			$(TEST_IMAGE)

sysbox: ## Build sysbox
sysbox: test-img
	@printf "\n** Building sysbox **\n\n"
	$(DOCKER_SYSBOX_BLD) /bin/bash -c "buildContainerInit sysbox-local"

sysbox-debug: ## Build sysbox (with debug symbols)
sysbox-debug: test-img
	@printf "\n** Building sysbox **\n\n"
	$(DOCKER_SYSBOX_BLD) /bin/bash -c "buildContainerInit sysbox-debug-local"

sysbox-static: ## Build sysbox (static linking)
sysbox-static: test-img
	@printf "\n** Building sysbox **\n\n"
	$(DOCKER_SYSBOX_BLD) /bin/bash -c "buildContainerInit sysbox-static-local"

sysbox-local: sysbox-runc sysbox-fs sysbox-mgr
	@echo $(HOSTNAME) > .buildinfo

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
	@cd $(LIBSECCOMP_DIR) && ./autogen.sh && ./configure && make
	@echo "Building libseccomp completed."

#
# install targets (require root privileges)
#

##@ Installation targets

install: ## Install all sysbox binaries (requires root privileges)
	install -D -m0755 sysbox-fs/sysbox-fs $(INSTALL_DIR)/sysbox-fs
	install -D -m0755 sysbox-mgr/sysbox-mgr $(INSTALL_DIR)/sysbox-mgr
	install -D -m0755 sysbox-runc/sysbox-runc $(INSTALL_DIR)/sysbox-runc
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

DOCKER_RUN := docker run -it --privileged --rm --runtime=runc         \
			--hostname sysbox-test                        \
			--name sysbox-test                            \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(TEST_VOL1):/var/lib/docker               \
			-v $(TEST_VOL2):/var/lib/sysbox               \
			-v $(TEST_VOL3):/mnt/scratch                  \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			$(KERNEL_HEADERS_MOUNTS) \
			$(TEST_IMAGE)

# Must use "--cgroups private" as otherwise configuring Docker with systemd
# cgroup driver gets confused with the cgroup paths.
DOCKER_RUN_SYSTEMD := docker run -d --rm --runtime=runc --privileged  \
			--hostname sysbox-test                        \
			--name sysbox-test                            \
			--cgroupns private                            \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(TEST_VOL1):/var/lib/docker               \
			-v $(TEST_VOL2):/var/lib/sysbox               \
			-v $(TEST_VOL3):/mnt/scratch                  \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules:/lib/modules:ro               \
			$(KERNEL_HEADERS_MOUNTS)                      \
			--mount type=tmpfs,destination=/run           \
			--mount type=tmpfs,destination=/run/lock      \
			--mount type=tmpfs,destination=/tmp           \
			$(TEST_SYSTEMD_IMAGE)

DOCKER_EXEC := docker exec -it sysbox-test
DOCKER_STOP := docker stop -t0 sysbox-test

##@ Testing targets

test: ## Run all sysbox test suites
test: test-fs test-mgr test-runc test-sysbox test-sysbox-shiftuid test-sysbox-systemd

test-sysbox: ## Run sysbox integration tests
test-sysbox: test-img
	@printf "\n** Running sysbox integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"

test-sysbox-ci: ## Run sysbox integration tests (continuous integration)
test-sysbox-ci: test-img test-fs test-mgr
	@printf "\n** Running sysbox integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && make test-sysbox-local-ci TESTPATH=$(TESTPATH)"

test-sysbox-systemd: ## Run sysbox integration tests in a test container with systemd
test-sysbox-systemd: test-img-systemd
	@printf "\n** Running sysbox integration tests (with systemd) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP)

test-sysbox-shiftuid: ## Run sysbox integration tests with uid-shifting (shiftfs)
test-sysbox-shiftuid: test-img
ifeq ($(SHIFTUID_ON), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_UIDS=true && testContainerInit && \
		make test-sysbox-local TESTPATH=$(TESTPATH)"
endif

test-sysbox-shiftuid-ci: ## Run sysbox integration tests with uid-shifting (shiftfs) (continuous integration)
test-sysbox-shiftuid-ci: test-img test-fs test-mgr
ifeq ($(SHIFTUID_ON), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_UIDS=true && testContainerInit && \
		make test-sysbox-local-ci TESTPATH=$(TESTPATH)"
endif

test-sysbox-shiftuid-systemd: ## Run sysbox integration tests with uid-shifting (shiftfs) and systemd
test-sysbox-shiftuid-systemd: test-img-systemd
ifeq ($(SHIFTUID_ON), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting and systemd) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_UIDS=true && testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP)
endif

test-runc: ## Run sysbox-runc unit & integration tests
test-runc: $(LIBSECCOMP) sysbox-ipc
	@printf "\n** Running sysbox-runc unit & integration tests **\n\n"
	cd $(SYSRUNC_DIR) && make clean && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" test

test-fs: ## Run sysbox-fs unit tests
test-fs: $(LIBSECCOMP) test-img
	@printf "\n** Running sysbox-fs unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-fs-local"

test-mgr: ## Run sysbox-mgr unit tests
test-mgr: test-img
	@printf "\n** Running sysbox-mgr unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-mgr-local"

test-shell: ## Get a shell in the test container (useful for debug)
test-shell: test-img sysbox-runc-recvtty
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && /bin/bash"

test-shell-systemd: ## Get a shell in the test container that includes systemd (useful for debug)
test-shell-systemd: test-img-systemd
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec -it sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		testContainerInit && /bin/bash"

test-shell-shiftuid: ## Get a shell in the test container with uid-shifting
test-shell-shiftuid: test-img sysbox-runc-recvtty
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_UIDS=true && testContainerInit && /bin/bash"

test-shell-shiftuid-systemd: ## Get a shell in the test container that includes shiftfs & systemd (useful for debug)
test-shell-shiftuid-systemd: test-img-systemd
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN_SYSTEMD)
	docker exec -it sysbox-test /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		export SHIFT_UIDS=true && testContainerInit && /bin/bash"

test-img: ## Build test container image
test-img:
	@printf "\n** Building the test container **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_IMAGE) \
		-f Dockerfile.$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE) .

test-img-systemd: ## Build test container image that includes systemd
test-img-systemd: test-img
	@printf "\n** Building the test container image (includes systemd) **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_SYSTEMD_IMAGE) \
		-f $(TEST_SYSTEMD_DOCKERFILE) .

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
	@cp -f sysbox-mgr/sysbox-mgr sysbox-in-docker/
	@cp -f sysbox-runc/sysbox-runc sysbox-in-docker/
	@cp -f sysbox-fs/sysbox-fs sysbox-in-docker/
	@make -C $(SYSBOX_IN_DOCKER_DIR) $(filter-out $@,$(MAKECMDGOALS))

sysbox-in-docker-local: sysbox-local
	@cp sysbox-mgr/sysbox-mgr sysbox-in-docker/
	@cp sysbox-runc/sysbox-runc sysbox-in-docker/
	@cp sysbox-fs/sysbox-fs sysbox-in-docker/
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
	$(DOCKER_RUN) /bin/bash -c "export PHY_EGRESS_IFACE_MTU=$(EGRESS_IFACE_MTU) && \
		sindTestContainerInit && /bin/bash"

#
# Code Hygiene targets
#

lint: ## runs lint checker on sysbox source code and tests
lint: test-img
	@printf "\n** Building sysbox **\n\n"
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

shfmt: ## formats shell scripts in the repo; requires shfmt.
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
clean:
	cd $(SYSRUNC_DIR) && make clean
	cd $(SYSFS_DIR) && make clean
	cd $(SYSMGR_DIR) && make clean
	cd $(SYSIPC_DIR) && make clean

clean-libseccomp: ## Clean libseccomp
clean-libseccomp:
	cd $(LIBSECCOMP_DIR) && sudo make distclean

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
