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
	test-img test-cleanup \
	listRuncPkgs listFsPkgs listMgrPkgs \
	clean

SHELL := bash
HOSTNAME := $(shell hostname)

# Sysvisor's build-target locations.
SYSRUNC_DIR     := sysvisor-runc
SYSFS_DIR       := sysvisor-fs
SYSMGR_DIR      := sysvisor-mgr
SYSFS_GRPC_DIR  := sysvisor-ipc/sysvisorFsGrpc
SYSMGR_GRPC_DIR := sysvisor-ipc/sysvisorMgrGrpc

# Consider to have this one moved out within sysvisor-runc folder.
SYSRUNC_BUILDTAGS := seccomp apparmor

INSTALL_DIR := /usr/local/sbin
PROJECT := /root/nestybox/sysvisor

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

.DEFAULT: sysvisor

sysvisor: sysvisor-runc sysvisor-fs sysvisor-mgr
	@echo $(HOSTNAME) > .buildinfo

sysvisor-debug: sysvisor-runc-debug sysvisor-fs-debug sysvisor-mgr-debug

sysvisor-static: sysvisor-runc-static sysvisor-fs-static sysvisor-mgr-static

sysvisor-runc: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)"

sysvisor-runc-debug: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" sysvisor-runc-debug

sysvisor-runc-static: sysfs-grpc-proto sysmgr-grpc-proto
	@cd $(SYSRUNC_DIR) && make static

sysvisor-fs: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make

sysvisor-fs-debug: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make sysvisor-fs-debug

sysvisor-fs-static: sysfs-grpc-proto
	@cd $(SYSFS_DIR) && make sysvisor-fs-static

sysvisor-mgr: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make

sysvisor-mgr-debug: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make sysvisor-mgr-debug

sysvisor-mgr-static: sysmgr-grpc-proto
	@cd $(SYSMGR_DIR) && make sysvisor-mgr-static

sysfs-grpc-proto:
	@cd $(SYSFS_GRPC_DIR)/protobuf && make

sysmgr-grpc-proto:
	@cd $(SYSMGR_GRPC_DIR)/protobuf && make

#
# install targets (require root privileges)
#

install:
	install -D -m0755 sysvisor-fs/sysvisor-fs $(INSTALL_DIR)/sysvisor-fs
	install -D -m0755 sysvisor-mgr/sysvisor-mgr $(INSTALL_DIR)/sysvisor-mgr
	install -D -m0755 sysvisor-runc/sysvisor-runc $(INSTALL_DIR)/sysvisor-runc
	install -D -m0755 bin/sysvisor $(INSTALL_DIR)/sysvisor

uninstall:
	rm -f $(INSTALL_DIR)/sysvisor
	rm -f $(INSTALL_DIR)/sysvisor-fs
	rm -f $(INSTALL_DIR)/sysvisor-mgr
	rm -f $(INSTALL_DIR)/sysvisor-runc

#
# test targets
#

DOCKER_RUN := docker run -it --privileged --rm --hostname sysvisor-test \
			-v $(CURDIR):$(PROJECT)             \
			-v /lib/modules:/lib/modules:ro     \
			-v $(TEST_VOL1):/var/lib/docker     \
			-v $(TEST_VOL2):/var/lib/sysvisor   \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod    \
			$(TEST_IMAGE)

test: test-fs test-mgr test-runc test-sysvisor test-sysvisor-shiftuid

test-sysvisor: test-img
	@printf "\n** Running sysvisor integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && make test-sysvisor-local TESTPATH=$(TESTPATH)"

test-sysvisor-shiftuid: test-img
	@printf "\n** Running sysvisor integration tests (with uid shifting) **\n\n"
	SHIFT_UIDS=true $(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "SHIFT_UIDS=true testContainerInit && make test-sysvisor-local TESTPATH=$(TESTPATH)"

test-sysvisor-local:
	bats --tap tests$(TESTPATH)
	bats --tap tests/handlers$(TESTPATH)

test-runc: sysfs-grpc-proto sysmgr-grpc-proto
	@printf "\n** Running sysvisor-runc unit & integration tests **\n\n"
	cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" test

test-fs: test-img
	@printf "\n** Running sysvisor-fs unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-fs-local"

test-mgr: test-img
	@printf "\n** Running sysvisor-mgr unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-mgr-local"

test-shiftfs: test-img
	@printf "\n** Running shiftfs posix compliance tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make test-shiftfs-local SUITEPATH=/root/pjdfstest TESTPATH=/var/lib/sysvisor/shiftfs-test"

# must run as root; requires pjdfstest to be installed at $(SUITEPATH); $(TESTPATH) is the directory where shiftfs is mounted.
test-shiftfs-local:
	tests/scr/testShiftfs $(SUITEPATH) $(TESTPATH)

test-shell: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && /bin/bash"

test-shell-shiftuid: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	$(DOCKER_RUN) /bin/bash -c "SHIFT_UIDS=true testContainerInit && /bin/bash"

test-fs-local: sysfs-grpc-proto
	cd $(SYSFS_DIR) && go test -timeout 3m -v $(fsPkgs)

test-mgr-local: sysmgr-grpc-proto
	cd $(SYSMGR_DIR) && go test -timeout 3m -v $(mgrPkgs)

test-img:
	@printf "\n** Building the test container **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_IMAGE) .

# must run as root
test-cleanup: test-img
	@printf "\n** Cleaning up sysvisor integration tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "testContainerCleanup"
	$(TEST_DIR)/scr/testContainerPost $(TEST_VOL1) $(TEST_VOL2)

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
