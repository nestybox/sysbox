#
# Sysvisor Makefile
#
# TODO:
# - fix grpc source deps for sysvisor targets; they are not working (which forces user to make clean & rebuild when grpc files change)
# - Add test targets (all-unit, all-integration, sysvisor-runc unit, sysvisor-runc integration, sysvisor-fs unit)
# - Add installation package target

.PHONY: all sysvisor sysvisor-static sysvisor-runc sysvisor-runc-static sysvisor-fs sysvisor-fs-static sysfs-grpc-proto install integration

SHELL := bash

CWD := $(CURDIR)

RUNC_DIR := $(GOPATH)/src/github.com/opencontainers/runc
BIN_DIR := /usr/local/sbin

SYSFS_SRC := $(shell find sysvisor-fs 2>&1 | grep -E '.*\.(c|h|go)$$')
SYSFS_GRPC_DIR := sysvisor-protobuf/sysvisorFsGrpc
SYSFS_GRPC_SRC := $(shell find $(SYSFS_GRPC_DIR) 2>&1 | grep -E '.*\.(c|h|go)$$')

SYSMGR_SRC := $(shell find sysvisor-mgr 2>&1 | grep -E '.*\.(c|h|go)$$')
SYSMGR_GRPC_DIR := sysvisor-protobuf/sysvisorMgrGrpc
SYSMGR_GRPC_SRC := $(shell find $(SYSMGR_GRPC_DIR) 2>&1 | grep -E '.*\.(c|h|go)$$')

.DEFAULT: sysvisor

all: sysvisor

static: sysvisor-static

sysvisor: sysvisor-runc sysvisor-fs sysvisor-mgr

sysvisor-static: sysvisor-runc-static sysvisor-fs-static sysvisor-mgr-static

sysvisor-runc: $(SYSFS_GRPC_SRC) $(SYSMGR_GRPC_SRC) sysfs-grpc-proto sysmgr-grpc-proto
	cd $(RUNC_DIR) && make

sysvisor-runc-static: $(SYSFS_GRPC_SRC) $(SYSMGR_GRPC_SRC) sysfs-grpc-proto sysmgr-grpc-proto
	cd $(RUNC_DIR) && make static

sysvisor-fs: $(SYSFS_SRC) $(SYSFS_GRPC_SRC) sysfs-grpc-proto
	go build -o sysvisor-fs/sysvisor-fs ./sysvisor-fs/cmd/sysvisor-fs

sysvisor-fs-static: $(SYSFS_SRC) $(SYSFS_GRPC_SRC) sysfs-grpc-proto
	CGO_ENABLED=1 go build -tags "netgo osusergo static_build" -installsuffix netgo -ldflags "-w -extldflags -static" -o sysvisor-fs/sysvisor-fs ./sysvisor-fs/cmd/sysvisor-fs

sysvisor-mgr: $(SYSMGR_SRC) $(SYSMGR_GRPC_SRC) sysmgr-grpc-proto
	go build -o sysvisor-mgr/sysvisor-mgr ./sysvisor-mgr

sysvisor-mgr-static: $(SYSMGR_SRC) $(SYSMGR_GRPC_SRC) sysmgr-grpc-proto
	CGO_ENABLED=1 go build -tags "netgo osusergo static_build" -installsuffix netgo -ldflags "-w -extldflags -static" -o sysvisor-mgr/sysvisor-mgr ./sysvisor-mgr

sysfs-grpc-proto:
	cd $(SYSFS_GRPC_DIR)/protobuf && make

sysmgr-grpc-proto:
	cd $(SYSMGR_GRPC_DIR)/protobuf && make

install:
	install -D -m0755 sysvisor-runc/sysvisor-runc $(BIN_DIR)/sysvisor-runc
	install -D -m0755 sysvisor-fs/sysvisor-fs $(BIN_DIR)/sysvisor-fs
	install -D -m0755 sysvisor-mgr/sysvisor-mgr $(BIN_DIR)/sysvisor-mgr

uninstall:
	rm -f $(BIN_DIR)/sysvisor-runc
	rm -f $(BIN_DIR)/sysvisor-fs
	rm -f $(BIN_DIR)/sysvisor-mgr

# sysvisor-test runs tests that verify sysvisor as a whole (i.e., sysvisor-runc + sysvisor-fs).
#
# NOTE: before running this target, see the requirements in file nestybox/sysvisor/tests/README
sysvisor-test: all
	bats --tap tests${TESTPATH}

clean:
	cd $(GOPATH)/src/github.com/opencontainers/runc && make clean
	cd $(SYSFS_GRPC_DIR)/protobuf && make clean
	cd $(SYSMGR_GRPC_DIR)/protobuf && make clean
	rm -f sysvisor-fs/sysvisor-fs
	rm -f sysvisor-mgr/sysvisor-mgr
