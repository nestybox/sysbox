#
# Sysboxd Makefile
#
# TODO:
# - Add installation package target

.PHONY: sysboxd sysboxd-static \
	sysbox-runc sysbox-runc-static sysbox-runc-debug \
	sysbox-fs sysbox-fs-static sysbox-fs-debug \
	sysbox-mgr sysbox-mgr-static sysbox-mgr-debug \
	sysfs-grpc-proto sysmgr-grpc-proto \
	install uninstall \
	test \
	test-sysboxd test-sysboxd-shiftuid test-sysboxd-local \
	test-runc test-fs test-mgr \
	test-shell test-shell-shiftuid \
	test-fs-local test-mgr-local \
	test-shiftfs test-shiftfs-local \
	test-img test-cleanup \
	listRuncPkgs listFsPkgs listMgrPkgs \
	pjdfstest pjdfstest-clean \
	clean

export SHELL=bash

# Global env-vars to carry metadata associated to image-builds. This state will
# be consumed by the sysboxd submodules and exposed through the --version cli option.
export VERSION=${shell cat ./VERSION}
export BUILT_AT=${shell date}
# We don't want previously-set env-vars to be reset should this makefile is
# ever visited again in the same building cycle (i.e. docker image builders).
ifeq ($(COMMIT_ID),)
export COMMIT_ID=$(shell git rev-parse --short HEAD)
endif
ifeq ($(BUILT_BY),)
export BUILT_BY=${USER}
endif
ifeq ($(HOSTNAME),)
export HOSTNAME=$(shell hostname)
endif


# Source-code paths of the sysboxd binary targets.
SYSRUNC_DIR     := sysbox-runc
SYSFS_DIR       := sysbox-fs
SYSMGR_DIR      := sysbox-mgr
SYSFS_GRPC_DIR  := sysbox-ipc/sysboxFsGrpc
SYSMGR_GRPC_DIR := sysbox-ipc/sysboxMgrGrpc
SHIFTFS_DIR     := shiftfs

# Consider to have this one moved out within sysbox-runc folder.
SYSRUNC_BUILDTAGS := seccomp apparmor

PROJECT := /root/nestybox/sysboxd

# Sysboxd binary targets destination.
ifeq ($(DESTDIR),)
INSTALL_DIR := /usr/local/sbin
else
INSTALL_DIR := ${DESTDIR}
endif

TEST_DIR := $(CURDIR)/tests
TEST_IMAGE := sysboxd-test

# volumes to mount into the privileged test container's `/var/lib/docker` and
# `/var/lib/sysboxd`; this is required so that the docker and sysbox-runc instances
# inside the privileged container do not run on top of overlayfs as this is not
# supported. The volumes must not be on a tmpfs directory, as the docker instance inside
# the privileged test container will mount overlayfs on top, and overlayfs can't be
# mounted on top of tmpfs.
TEST_VOL1 := /var/tmp/sysboxd-test-var-lib-docker
TEST_VOL2 := /var/tmp/sysboxd-test-var-lib-sysboxd

#
# build targets
# TODO: parallelize building of runc, fs, and mgr; note that grpc must be built before these.
#

.DEFAULT := help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Building targets

sysboxd: ## Build all sysboxd modules
sysboxd: sysbox-runc sysbox-fs sysbox-mgr
	@echo $(HOSTNAME) > .buildinfo

sysboxd-debug: ## Build all sysboxd modules (compiler optimizations off)
sysboxd-debug: sysbox-runc-debug sysbox-fs-debug sysbox-mgr-debug

sysboxd-static: ## Build all sysboxd modules (static linking)
sysboxd-static: sysbox-runc-static sysbox-fs-static sysbox-mgr-static

sysbox-runc: ## Build sysbox-runc module
sysbox-runc: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)"

sysbox-runc-debug: ## Build sysbox-runc module (compiler optimizations off)
sysbox-runc-debug: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" sysbox-runc-debug

sysbox-runc-static: ## Build sysbox-runc module (static linking)
sysbox-runc-static: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make static

sysbox-fs: ## Build sysbox-fs module
sysbox-fs: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make

sysbox-fs-debug: ## Build sysbox-fs module (compiler optimizations off)
sysbox-fs-debug: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make sysbox-fs-debug

sysbox-fs-static: ## Build sysbox-fs module (static linking)
sysbox-fs-static: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make sysbox-fs-static

sysbox-mgr: ## Build sysbox-mgr module
sysbox-mgr: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make

sysbox-mgr-debug: ## Build sysbox-mgr module (compiler optimizations off)
sysbox-mgr-debug: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make sysbox-mgr-debug

sysbox-mgr-static: ## Build sysbox-mgr module (static linking)
sysbox-mgr-static: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make sysbox-mgr-static

sysfs-grpc-proto:
	@cd $(SYSFS_GRPC_DIR)/protobuf && make

sysmgr-grpc-proto:
	@cd $(SYSMGR_GRPC_DIR)/protobuf && make

#
# install targets (require root privileges)
#

##@ Installation targets

install: ## Install all sysboxd binaries
	install -D -m0755 sysbox-fs/sysbox-fs $(INSTALL_DIR)/sysbox-fs
	install -D -m0755 sysbox-mgr/sysbox-mgr $(INSTALL_DIR)/sysbox-mgr
	install -D -m0755 sysbox-runc/sysbox-runc $(INSTALL_DIR)/sysbox-runc
	install -D -m0755 bin/sysboxd $(INSTALL_DIR)/sysboxd

uninstall: ## Uninstall all sysboxd binaries
	rm -f $(INSTALL_DIR)/sysboxd
	rm -f $(INSTALL_DIR)/sysbox-fs
	rm -f $(INSTALL_DIR)/sysbox-mgr
	rm -f $(INSTALL_DIR)/sysbox-runc

#
# test targets
# (these run within a test container, so they won't messup your host)
#

DOCKER_RUN := docker run -it --privileged --rm --hostname sysboxd-test \
			-v $(CURDIR):$(PROJECT)             \
			-v /lib/modules:/lib/modules:ro     \
			-v $(TEST_VOL1):/var/lib/docker     \
			-v $(TEST_VOL2):/var/lib/sysboxd   \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod    \
			$(TEST_IMAGE)

##@ Testing targets

test: ## Run all sysboxd tests suites
test: test-fs test-mgr test-runc test-sysboxd test-sysboxd-shiftuid

test-sysboxd: ## Run sysboxd integration tests
test-sysboxd: test-img
	@printf "\n** Running sysboxd integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && make test-sysboxd-local TESTPATH=$(TESTPATH)"

test-sysboxd-shiftuid: ## Run sysboxd intergration tests with uid-shifting
test-sysboxd-shiftuid: test-img
	@printf "\n** Running sysboxd integration tests (with uid shifting) **\n\n"
	SHIFT_UIDS=true $(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "export SHIFT_UIDS=true && testContainerInit && make test-sysboxd-local TESTPATH=$(TESTPATH)"

test-runc: ## Run sysbox-runc unit & integration tests
test-runc: sysfs-grpc-proto sysmgr-grpc-proto
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

test-shiftfs: ## Run shiftfs tests
test-shiftfs: test-img
	@printf "\n** Running shiftfs tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make test-shiftfs-local TESTPATH=$(TESTPATH)"
	$(DOCKER_RUN) /bin/bash -c "make test-shiftfs-ovfs-local TESTPATH=$(TESTPATH)"
	$(DOCKER_RUN) /bin/bash -c "make test-shiftfs-tmpfs-local TESTPATH=$(TESTPATH)"

test-shiftfs-cleanup: ## Cleanup shiftfs test suite
test-shiftfs-cleanup: pjdfstest-clean

test-shell: ## Get a shell in the test container (useful for debug)
test-shell: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && /bin/bash"

test-shell-shiftuid: ## Get a shell in the test container with uid-shifting
test-shell-shiftuid: test-img
	SHIFT_UIDS=true $(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "export SHIFT_UIDS=true && testContainerInit && /bin/bash"

test-img: ## Build test container image
test-img:
	@printf "\n** Building the test container **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_IMAGE) .

test-cleanup: ## Clean up sysboxd integration tests (to be run as root)
test-cleanup: test-img
	@printf "\n** Cleaning up sysboxd integration tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "testContainerCleanup"
	$(TEST_DIR)/scr/testContainerPost $(TEST_VOL1) $(TEST_VOL2)

#
# Local test targets (these are invoked from within the test container
# by the test target above); in theory they can run directly on a dev
# machine, but they require root privileges and might messup the state
# of the host.
#

test-sysboxd-local:
	$(TEST_DIR)/scr/testSysboxd $(TESTPATH)

test-shiftfs-local: pjdfstest
	@printf "\n** shiftfs only mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs /var/lib/sysboxd $(TESTPATH)

test-shiftfs-ovfs-local: pjdfstest
	@printf "\n** shiftfs + overlayfs mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs -m overlayfs /var/lib/sysboxd $(TESTPATH)

test-shiftfs-tmpfs-local: pjdfstest
	@printf "\n** shiftfs + tmpfs mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs -m tmpfs /var/lib/sysboxd $(TESTPATH)

test-fs-local: sysfs-grpc-proto
	cd $(SYSFS_DIR) && go test -timeout 3m -v $(fsPkgs)

test-mgr-local: sysmgr-grpc-proto
	cd $(SYSMGR_DIR) && go test -timeout 3m -v $(mgrPkgs)

#
# Images targets
#

##@ Images handling targets

image: ## Image creation / elimination sub-menu
	$(MAKE) -C images --no-print-directory $(filter-out $@,$(MAKECMDGOALS))

#
# Misc targets
#

# must run as root
pjdfstest: $(SHIFTFS_DIR)/pjdfstest/pjdfstest
	cp shiftfs/pjdfstest/pjdfstest /usr/local/bin

$(SHIFTFS_DIR)/pjdfstest/pjdfstest:
	cd shiftfs/pjdfstest && autoreconf -ifs && ./configure && make pjdfstest

pjdfstest-clean:
	cd $(SHIFTFS_DIR)/pjdfstest && ./cleanup.sh

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

clean: ## Eliminate sysboxd binaries
clean:
	cd $(SYSRUNC_DIR) && make clean
	cd $(SYSFS_DIR) && make clean
	cd $(SYSMGR_DIR) && make clean
	cd $(SYSFS_GRPC_DIR)/protobuf && make clean
	cd $(SYSMGR_GRPC_DIR)/protobuf && make clean

# memoize all packages once

_runcPkgs = $(shell cd $(SYSRUNC_DIR) && go list ./... | grep -v vendor)
runcPkgs = $(if $(__runcPkgs),,$(eval __runcPkgs := $$(_runcPkgs)))$(__runcPkgs)

_fsPkgs = $(shell cd $(SYSFS_DIR) && go list ./... | grep -v vendor)
fsPkgs = $(if $(__fsPkgs),,$(eval __fsPkgs := $$(_fsPkgs)))$(__fsPkgs)

_mgrPkgs = $(shell cd $(SYSMGR_DIR) && go list ./... | grep -v vendor)
mgrPkgs = $(if $(__mgrPkgs),,$(eval __mgrPkgs := $$(_mgrPkgs)))$(__mgrPkgs)
