#
# Sysvisor Makefile
#
# TODO:
# - Add installation package target

.PHONY: sysvisor sysvisor-static \
	sysvisor-runc sysvisor-runc-static sysvisor-runc-debug \
	sysvisor-fs sysvisor-fs-static sysvisor-fs-debug \
	sysvisor-mgr sysvisor-mgr-static sysvisor-mgr-debug \
	sysfs-grpc-proto sysmgr-grpc-proto \
	install uninstall \
	test \
	test-sysvisor test-sysvisor-shiftuid test-sysvisor-local \
	test-runc test-fs test-mgr \
	test-shell test-shell-shiftuid \
	test-fs-local test-mgr-local \
	test-shiftfs test-shiftfs-local \
	test-img test-cleanup \
	listRuncPkgs listFsPkgs listMgrPkgs \
	pjdfstest pjdfstest-clean \
	clean

SHELL := bash
HOSTNAME := $(shell hostname)

# Source-code paths of Sysvisor's binary targets.
SYSRUNC_DIR     := sysvisor-runc
SYSFS_DIR       := sysvisor-fs
SYSMGR_DIR      := sysvisor-mgr
SYSFS_GRPC_DIR  := sysvisor-ipc/sysvisorFsGrpc
SYSMGR_GRPC_DIR := sysvisor-ipc/sysvisorMgrGrpc
SHIFTFS_DIR     := shiftfs

# Consider to have this one moved out within sysvisor-runc folder.
SYSRUNC_BUILDTAGS := seccomp apparmor

PROJECT := /root/nestybox/sysvisor

# Sysvisor's binary targets destination.
ifeq ($(DESTDIR),)
INSTALL_DIR := /usr/local/sbin
else
INSTALL_DIR := ${DESTDIR}
endif

TEST_DIR := $(CURDIR)/tests
TEST_IMAGE := sysvisor-test

# volumes to mount into the privileged test container's `/var/lib/docker` and
# `/var/lib/sysvisor`; this is required so that the docker and sysvisor-runc instances
# inside the privileged container do not run on top of overlayfs as this is not
# supported. The volumes must not be on a tmpfs directory, as the docker instance inside
# the privileged test container will mount overlayfs on top, and overlayfs can't be
# mounted on top of tmpfs.
TEST_VOL1 := /var/tmp/sysvisor-test-var-lib-docker
TEST_VOL2 := /var/tmp/sysvisor-test-var-lib-sysvisor

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

sysvisor: ## Build all sysvisor modules
sysvisor: sysvisor-runc sysvisor-fs sysvisor-mgr
	@echo $(HOSTNAME) > .buildinfo

sysvisor-debug: ## Build all sysvisor modules (compiler optimizations off)
sysvisor-debug: sysvisor-runc-debug sysvisor-fs-debug sysvisor-mgr-debug

sysvisor-static: ## Build all sysvisor modules (static linking)
sysvisor-static: sysvisor-runc-static sysvisor-fs-static sysvisor-mgr-static

sysvisor-runc: ## Build sysvisor-runc module
sysvisor-runc: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)"

sysvisor-runc-debug: ## Build sysvisor-runc module (compiler optimizations off)
sysvisor-runc-debug: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" sysvisor-runc-debug

sysvisor-runc-static: ## Build sysvisor-runc module (static linking)
sysvisor-runc-static: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make static

sysvisor-fs: ## Build sysvisor-fs module
sysvisor-fs: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make

sysvisor-fs-debug: ## Build sysvisor-fs module (compiler optimizations off)
sysvisor-fs-debug: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make sysvisor-fs-debug

sysvisor-fs-static: ## Build sysvisor-fs module (static linking)
sysvisor-fs-static: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make sysvisor-fs-static

sysvisor-mgr: ## Build sysvisor-mgr module
sysvisor-mgr: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make

sysvisor-mgr-debug: ## Build sysvisor-mgr module (compiler optimizations off)
sysvisor-mgr-debug: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make sysvisor-mgr-debug

sysvisor-mgr-static: ## Build sysvisor-mgr module (static linking)
sysvisor-mgr-static: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make sysvisor-mgr-static

sysfs-grpc-proto:
	@cd $(SYSFS_GRPC_DIR)/protobuf && make

sysmgr-grpc-proto:
	@cd $(SYSMGR_GRPC_DIR)/protobuf && make

#
# install targets (require root privileges)
#

##@ Installation targets

install: ## Install all sysvisor binaries
	install -D -m0755 sysvisor-fs/sysvisor-fs $(INSTALL_DIR)/sysvisor-fs
	install -D -m0755 sysvisor-mgr/sysvisor-mgr $(INSTALL_DIR)/sysvisor-mgr
	install -D -m0755 sysvisor-runc/sysvisor-runc $(INSTALL_DIR)/sysvisor-runc
	install -D -m0755 bin/sysvisor $(INSTALL_DIR)/sysvisor

uninstall: ## Uninstall all sysvisor binaries
	rm -f $(INSTALL_DIR)/sysvisor
	rm -f $(INSTALL_DIR)/sysvisor-fs
	rm -f $(INSTALL_DIR)/sysvisor-mgr
	rm -f $(INSTALL_DIR)/sysvisor-runc

#
# test targets
# (these run within a test container, so they won't messup your host)
#

DOCKER_RUN := docker run -it --privileged --rm --hostname sysvisor-test \
			-v $(CURDIR):$(PROJECT)             \
			-v /lib/modules:/lib/modules:ro     \
			-v $(TEST_VOL1):/var/lib/docker     \
			-v $(TEST_VOL2):/var/lib/sysvisor   \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod    \
			$(TEST_IMAGE)

##@ Testing targets

test: ## Run all sysvisor tests suites
test: test-fs test-mgr test-runc test-sysvisor test-sysvisor-shiftuid

test-sysvisor: ## Run sysvisor integration tests
test-sysvisor: test-img
	@printf "\n** Running sysvisor integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && make test-sysvisor-local TESTPATH=$(TESTPATH)"

test-sysvisor-shiftuid: ## Run sysvisor intergration tests with uid-shifting
test-sysvisor-shiftuid: test-img
	@printf "\n** Running sysvisor integration tests (with uid shifting) **\n\n"
	SHIFT_UIDS=true $(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "export SHIFT_UIDS=true && testContainerInit && make test-sysvisor-local TESTPATH=$(TESTPATH)"

test-runc: ## Run sysvisor-runc unit & integration tests
test-runc: sysfs-grpc-proto sysmgr-grpc-proto
	@printf "\n** Running sysvisor-runc unit & integration tests **\n\n"
	cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" test

test-fs: ## Run sysvisor-fs unit tests
test-fs: test-img
	@printf "\n** Running sysvisor-fs unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-fs-local"

test-mgr: ## Run sysvisor-mgr unit tests
test-mgr: test-img
	@printf "\n** Running sysvisor-mgr unit tests **\n\n"
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

test-cleanup: ## Clean up sysvisor integration tests (to be run as root)
test-cleanup: test-img
	@printf "\n** Cleaning up sysvisor integration tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "testContainerCleanup"
	$(TEST_DIR)/scr/testContainerPost $(TEST_VOL1) $(TEST_VOL2)

#
# Local test targets (these are invoked from within the test container
# by the test target above); in theory they can run directly on a dev
# machine, but they require root privileges and might messup the state
# of the host.
#

test-sysvisor-local:
	$(TEST_DIR)/scr/testSysvisor $(TESTPATH)

test-shiftfs-local: pjdfstest
	@printf "\n** shiftfs only mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs /var/lib/sysvisor $(TESTPATH)

test-shiftfs-ovfs-local: pjdfstest
	@printf "\n** shiftfs + overlayfs mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs -m overlayfs /var/lib/sysvisor $(TESTPATH)

test-shiftfs-tmpfs-local: pjdfstest
	@printf "\n** shiftfs + tmpfs mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs -m tmpfs /var/lib/sysvisor $(TESTPATH)

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

clean: ## Eliminate sysvisor binaries
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
