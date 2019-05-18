#
# Sysvisor Makefile
#
# TODO:
# - fix grpc source deps for sysvisor targets; they are not working (which forces user to make clean & rebuild when grpc files change)
# - Add test targets (all-unit, all-integration, sysvisor-runc unit, sysvisor-runc integration, sysvisor-fs unit)
# - Add installation package target

.PHONY: sysvisor sysvisor-static \
	sysvisor-runc sysvisor-runc-static \
	sysvisor-fs sysvisor-fs-static sysvisor-fs-debug \
	sysvisor-mgr sysvisor-mgr-static sysvisor-mgr-debug \
	sysfs-grpc-proto sysmgr-grpc-proto \
	install integration \
	test-img test-shell \
	test test-sysvisor test-sysvisor-local \
	test-runc test-fs test-mgr \
	test-fs-local test-mgr-local

SHELL := bash

RUNC_GO_DIR := $(GOPATH)/src/github.com/opencontainers/runc
RUNC_BUILDTAGS := seccomp apparmor

INSTALL_DIR := /usr/local/sbin
PROJECT := github.com/nestybox/sysvisor

SYSFS_GO_DIR := $(GOPATH)/src/$(PROJECT)/sysvisor-fs
SYSFS_SRC := $(shell find sysvisor-fs 2>&1 | grep -E '.*\.(c|h|go)$$')
SYSFS_GRPC_DIR := sysvisor-ipc/sysvisorFsGrpc
SYSFS_GRPC_SRC := $(shell find $(SYSFS_GRPC_DIR) 2>&1 | grep -E '.*\.(c|h|go)$$')

SYSMGR_GO_DIR := $(GOPATH)/src/$(PROJECT)/sysvisor-mgr
SYSMGR_SRC := $(shell find sysvisor-mgr 2>&1 | grep -E '.*\.(c|h|go)$$')
SYSMGR_GRPC_DIR := sysvisor-ipc/sysvisorMgrGrpc
SYSMGR_GRPC_SRC := $(shell find $(SYSMGR_GRPC_DIR) 2>&1 | grep -E '.*\.(c|h|go)$$')

TEST_DIR := $(CURDIR)/tests
TEST_IMAGE := sysvisor-test

# test volumes to mount into the test container
# NOTE: must not be on tmpfs directory, as docker's overlayfs may not work well on top of tmpfs.
TEST_VOL1 := /var/tmp/sysvisor-test-l1-var-lib-docker
TEST_VOL2 := /var/tmp/sysvisor-test-l2-var-lib-docker

#
# build targets
#
# TODO: parallelize building of runc, fs, and mgr; note that grpc must be build before these.
#

.DEFAULT: sysvisor

sysvisor: sysvisor-runc sysvisor-fs sysvisor-mgr

sysvisor-debug: sysvisor-runc-debug sysvisor-fs-debug sysvisor-mgr-debug

sysvisor-static: sysvisor-runc-static sysvisor-fs-static sysvisor-mgr-static

sysvisor-runc: $(SYSFS_GRPC_SRC) $(SYSMGR_GRPC_SRC) sysfs-grpc-proto sysmgr-grpc-proto
	cd $(RUNC_GO_DIR) && make BUILDTAGS="$(RUNC_BUILDTAGS)"

sysvisor-runc-debug: $(SYSFS_GRPC_SRC) $(SYSMGR_GRPC_SRC) sysfs-grpc-proto sysmgr-grpc-proto
	cd $(RUNC_GO_DIR) && make BUILDTAGS="$(RUNC_BUILDTAGS)" sysvisor-runc-debug

sysvisor-runc-static: $(SYSFS_GRPC_SRC) $(SYSMGR_GRPC_SRC) sysfs-grpc-proto sysmgr-grpc-proto
	cd $(RUNC_GO_DIR) && make static

sysvisor-fs: $(SYSFS_SRC) $(SYSFS_GRPC_SRC) sysfs-grpc-proto
	cd $(SYSFS_GO_DIR) && go build -o sysvisor-fs ./cmd/sysvisor-fs

sysvisor-fs-debug: $(SYSFS_SRC) $(SYSFS_GRPC_SRC) sysfs-grpc-proto
	cd $(SYSFS_GO_DIR) && go build -gcflags="all=-N -l" -o sysvisor-fs ./cmd/sysvisor-fs

sysvisor-fs-static: $(SYSFS_SRC) $(SYSFS_GRPC_SRC) sysfs-grpc-proto
	cd $(SYSFS_GO_DIR) && CGO_ENABLED=1 go build -tags "netgo osusergo static_build" -installsuffix netgo -ldflags "-w -extldflags -static" -o sysvisor-fs ./cmd/sysvisor-fs

sysvisor-mgr: $(SYSMGR_SRC) $(SYSMGR_GRPC_SRC) sysmgr-grpc-proto
	cd $(SYSMGR_GO_DIR) && go build -o sysvisor-mgr

sysvisor-mgr-debug: $(SYSMGR_SRC) $(SYSMGR_GRPC_SRC) sysmgr-grpc-proto
	cd $(SYSMGR_GO_DIR) && go build -gcflags="all=-N -l" -o sysvisor-mgr

sysvisor-mgr-static: $(SYSMGR_SRC) $(SYSMGR_GRPC_SRC) sysmgr-grpc-proto
	cd $(SYSMGR_GO_DIR) && CGO_ENABLED=1 go build -tags "netgo osusergo static_build" -installsuffix netgo -ldflags "-w -extldflags -static" -o sysvisor-mgr

sysfs-grpc-proto:
	cd $(SYSFS_GRPC_DIR)/protobuf && make

sysmgr-grpc-proto:
	cd $(SYSMGR_GRPC_DIR)/protobuf && make

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
# NOTE: targets test-sysvisor and test-shell require root privileges (otherwise they will
# fail to remove TEST_VOL*)
#
# TODO: bind mount TEST_VOL2 to an appropriate dir in the (level-1) sysvisor-test container; the
# expectation is that sysvisor instance inside the container will then bind-mount that
# directory into the (level-2) sys containers. This will then allow each level-2 docker
# instance (docker inside the sys container) to create the (level-3) app container.
#

test: test-fs test-mgr test-runc test-sysvisor

test-sysvisor: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	docker run -it --privileged --rm --hostname sysvisor-test -v $(CURDIR):/go/src/$(PROJECT) -v /lib/modules:/lib/modules:ro -v $(TEST_VOL1):/var/lib/docker $(TEST_IMAGE) /bin/bash -c "testContainerInit && make test-sysvisor-local TESTPATH=$(TESTPATH)"
	$(TEST_DIR)/scr/testContainerPost $(TEST_VOL1) $(TEST_VOL2)

test-sysvisor-local:
	bats --tap tests$(TESTPATH)

test-runc: sysfs-grpc-proto sysmgr-grpc-proto
	cd $(RUNC_GO_DIR) && make BUILDTAGS="$(RUNC_BUILDTAGS)" test

test-fs:
	docker run -it --privileged --rm --hostname sysvisor-test -v $(CURDIR):/go/src/$(PROJECT) -v /lib/modules:/lib/modules:ro -v $(TEST_VOL1):/var/lib/docker $(TEST_IMAGE) /bin/bash -c "make test-fs-local"

test-mgr:
	docker run -it --privileged --rm --hostname sysvisor-test -v $(CURDIR):/go/src/$(PROJECT) -v /lib/modules:/lib/modules:ro -v $(TEST_VOL1):/var/lib/docker $(TEST_IMAGE) /bin/bash -c "make test-mgr-local"

test-shell: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2)
	docker run -it --privileged --rm --hostname sysvisor-test -v $(CURDIR):/go/src/$(PROJECT) -v /lib/modules:/lib/modules:ro -v $(TEST_VOL1):/var/lib/docker $(TEST_IMAGE) /bin/bash -c "testContainerInit && /bin/bash"
	$(TEST_DIR)/scr/testContainerPost $(TEST_VOL1) $(TEST_VOL2)

test-fs-local: sysfs-grpc-proto
	cd $(SYSFS_GO_DIR) && go test -timeout 3m -v $(fsPkgs)

test-mgr-local: sysmgr-grpc-proto
	cd $(SYSMGR_GO_DIR) && go test -timeout 3m -v $(mgrPkgs)

test-img:
	cd $(TEST_DIR) && docker build -t $(TEST_IMAGE) .

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
	cd $(GOPATH)/src/github.com/opencontainers/runc && make clean
	cd $(SYSFS_GRPC_DIR)/protobuf && make clean
	cd $(SYSMGR_GRPC_DIR)/protobuf && make clean
	rm -f sysvisor-fs/sysvisor-fs
	rm -f sysvisor-mgr/sysvisor-mgr

# memoize all packages once

_runcPkgs = $(shell cd $(RUNC_GO_DIR) && go list ./... | grep -v vendor)
runcPkgs = $(if $(__runcPkgs),,$(eval __runcPkgs := $$(_runcPkgs)))$(__runcPkgs)

_fsPkgs = $(shell cd $(SYSFS_GO_DIR) && go list ./... | grep -v vendor)
fsPkgs = $(if $(__fsPkgs),,$(eval __fsPkgs := $$(_fsPkgs)))$(__fsPkgs)

_mgrPkgs = $(shell cd $(SYSMGR_GO_DIR) && go list ./... | grep -v vendor)
mgrPkgs = $(if $(__mgrPkgs),,$(eval __mgrPkgs := $$(_mgrPkgs)))$(__mgrPkgs)
