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
	test-sysbox test-sysbox-shiftuid test-sysbox-local \
	test-runc test-fs test-mgr \
	test-shell test-shell-shiftuid \
	test-fs-local test-mgr-local \
	test-img test-cleanup \
	listRuncPkgs listFsPkgs listMgrPkgs \
	pjdfstest pjdfstest-clean \
	build-deb ubuntu-bionic ubuntu-cosmic ubuntu-disco ubuntu-eoan ubuntu-focal \
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
LIB_SECCOMP_DIR := sysbox-libs/libseccomp-golang

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

# Host kernel info
KERNEL_REL := $(shell uname -r)

# Sysbox image-generation globals utilized during the testing of sysbox installer.
IMAGE_BASE_DISTRO := $(shell lsb_release -ds | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
IMAGE_BASE_RELEASE := $(shell lsb_release -cs)

# Volumes to mount into the privileged test container. These are
# required because certain mounts inside the test container can't
# be backed by overlayfs (e.g., /var/lib/docker, /var/lib/sysbox, etc.).
# Note that the volumes must not be on tmpfs either, because the
# docker engine inside the privileged test container will mount overlayfs
# on top , and overlayfs can't be mounted on top of tmpfs.
TEST_VOL1 := /var/tmp/sysbox-test-var-lib-docker
TEST_VOL2 := /var/tmp/sysbox-test-var-lib-sysbox
TEST_VOL3 := /var/tmp/sysbox-test-scratch

# In scenarios where the egress-interface's mtu is lower than expected (1500 bytes),
# we must explicitly configure dockerd with such a value.
EGRESS_IFACE := $(shell ip route show | awk '/default via/ {print $$5}')
EGRESS_IFACE_MTU := $(shell ip link show dev $(EGRESS_IFACE) | awk '/mtu/ {print $$5}')

# Find out if 'shiftfs' module is present.
SHIFTUID_ON := $(shell modprobe shiftfs >/dev/null 2>&1 && lsmod | grep shiftfs)

#
# build targets
# TODO: parallelize building of runc, fs, and mgr; note that grpc must be built before these.
#

.DEFAULT := help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Building targets

DOCKER_SYSBOX_BLD := docker run --privileged --rm                     \
			--hostname sysbox-build                       \
			--name sysbox-build                           \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			-v /usr/src/$(HEADERS):/usr/src/$(HEADERS):ro \
			-v /usr/src/$(HEADERS_BASE):/usr/src/$(HEADERS_BASE):ro \
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

sysbox-runc-debug: sysbox-ipc
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" sysbox-runc-debug

sysbox-runc-static: sysbox-ipc
	@cd $(SYSRUNC_DIR) && make static

sysbox-fs: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSFS_DIR) && make

sysbox-fs-debug: sysbox-ipc
	@cd $(SYSFS_DIR) && make sysbox-fs-debug

sysbox-fs-static: sysbox-ipc
	@cd $(SYSFS_DIR) && make sysbox-fs-static

sysbox-mgr: sysbox-ipc
	@cd $(SYSMGR_DIR) && make

sysbox-mgr-debug: sysbox-ipc
	@cd $(SYSMGR_DIR) && make sysbox-mgr-debug

sysbox-mgr-static: sysbox-ipc
	@cd $(SYSMGR_DIR) && make sysbox-mgr-static

sysbox-ipc:
	@cd $(SYSIPC_DIR) && make sysbox-ipc

# libseccomp (used by Sysbox components)
LIBSECCOMP := sysbox-libs/libseccomp/src/.libs/libseccomp.a
LIBSECCOMP_DIR := sysbox-libs/libseccomp
LIBSECCOMP_SRC := $(shell find $(LIBSECCOMP_DIR)/src 2>&1 | grep -E '.*\.(c|h)')
LIBSECCOMP_SRC += $(shell find $(LIBSECCOMP_DIR)/include 2>&1 | grep -E '.*\.h')
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

HEADERS := linux-headers-$(KERNEL_REL)

# hacky: works on ubuntu but may not work on other distros
HEADERS_BASE := $(shell find /usr/src/$(HEADERS) -maxdepth 1 -type l -exec readlink {} \; | cut -d"/" -f2 | head -1)

# Alternative: reads symlinks and finds longest common prefix with sed (works on shell but fails on makefile for some reason)
# HEADERS_BASE := $(shell find /usr/src/$(HEADERS) -maxdepth 1 -type l -exec readlink -f {} \; | uniq | sed -e 's,$,/,;1{h;d;}' -e 'G;s,\(.*/\).*\n\1.*,\1,;h;$!d;s,/$,,' )

DOCKER_RUN := docker run -it --privileged --rm                        \
			--hostname sysbox-test                        \
			--name sysbox-test                            \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(TEST_VOL1):/var/lib/docker               \
			-v $(TEST_VOL2):/var/lib/sysbox               \
			-v $(TEST_VOL3):/mnt/scratch                  \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			-v /usr/src/$(HEADERS):/usr/src/$(HEADERS):ro \
			-v /usr/src/$(HEADERS_BASE):/usr/src/$(HEADERS_BASE):ro \
			$(TEST_IMAGE)


##@ Testing targets

test: ## Run all sysbox test suites
test: test-fs test-mgr test-runc test-sysbox test-sysbox-shiftuid

test-sysbox: ## Run sysbox integration tests
test-sysbox: test-img
	@printf "\n** Running sysbox integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"

test-sysbox-shiftuid: ## Run sysbox integration tests with uid-shifting (shiftfs)
test-sysbox-shiftuid: test-img
ifeq ($(SHIFTUID_ON), )
	@printf "\n** No shiftfs module found. Skipping $@ target. **\n\n"
else
	@printf "\n** Running sysbox integration tests (with uid shifting) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export SHIFT_UIDS=true && testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"
endif

test-runc: ## Run sysbox-runc unit & integration tests
test-runc: $(LIBSECCOMP) sysbox-ipc
	@printf "\n** Running sysbox-runc unit & integration tests **\n\n"
	cd $(SYSRUNC_DIR) && make clean && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" test

test-fs: ## Run sysbox-fs unit tests
test-fs: test-img
	@printf "\n** Running sysbox-fs unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-fs-local"

test-mgr: ## Run sysbox-mgr unit tests
test-mgr: test-img
	@printf "\n** Running sysbox-mgr unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-mgr-local"

test-shell: ## Get a shell in the test container (useful for debug)
test-shell: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && /bin/bash"

test-shell-shiftuid: ## Get a shell in the test container with uid-shifting
test-shell-shiftuid: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export SHIFT_UIDS=true && testContainerInit && /bin/bash"

test-img: ## Build test container image
test-img:
	@printf "\n** Building the test container **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_IMAGE) \
		-f Dockerfile.$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE) .

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

test-sysbox-local:
	$(TEST_DIR)/scr/testSysbox $(TESTPATH)

test-fs-local: sysbox-ipc
	cd $(SYSFS_DIR) && go test -timeout 3m -v $(fsPkgs)

test-mgr-local: sysbox-ipc
	dockerd > /var/log/dockerd.log 2>&1 &
	sleep 2
	cd $(SYSMGR_DIR) && go test -timeout 3m -v $(mgrPkgs)

#
# Misc targets
#

# recvtty is a tool inside the sysbox-runc repo that is needed by some integration tests
sysbox-runc-recvtty:
	@cd $(SYSRUNC_DIR) && make recvtty

#
# Misc targets
#

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

clean_libseccomp: ## Clean libseccomp
clean_libseccomp:
	cd $(LIBSECCOMP_DIR) && make clean

# memoize all packages once

_runcPkgs = $(shell cd $(SYSRUNC_DIR) && go list ./... | grep -v vendor)
runcPkgs = $(if $(__runcPkgs),,$(eval __runcPkgs := $$(_runcPkgs)))$(__runcPkgs)

_fsPkgs = $(shell cd $(SYSFS_DIR) && go list ./... | grep -v vendor)
fsPkgs = $(if $(__fsPkgs),,$(eval __fsPkgs := $$(_fsPkgs)))$(__fsPkgs)

_mgrPkgs = $(shell cd $(SYSMGR_DIR) && go list ./... | grep -v vendor)
mgrPkgs = $(if $(__mgrPkgs),,$(eval __mgrPkgs := $$(_mgrPkgs)))$(__mgrPkgs)
