#
# Sysvisor Makefile
#
# TODO:
# - Add test targets (all-unit, all-integration, sysvisor-runc unit, sysvisor-runc integration, sysvisor-fs unit)
# - Add installation package target

.PHONY: all sysvisor sysvisor-static sysvisor-runc sysvisor-runc-static sysvisor-fs sysvisor-fs-static install integration

SHELL:=bash

CWD := $(CURDIR)

RUNC_DIR := $(GOPATH)/src/github.com/opencontainers/runc
BIN_DIR := /usr/local/sbin

SYSFS_PROTO_GO=sysvisor-protobuf/sysvisor-protobuf.pb.go

SYSFS_SRC := $(shell find sysvisor-fs 2>&1 | grep -E '.*\.(c|h|go)$$')

.DEFAULT: sysvisor

all: sysvisor

static: sysvisor-static

sysvisor: $(SYSFS_PROTO_GO) sysvisor-runc sysvisor-fs

sysvisor-static: $(SYSFS_PROTO_GO) sysvisor-runc-static sysvisor-fs-static

sysvisor-runc: $(SYSFS_PROTO_GO)
	cd $(RUNC_DIR) && make

sysvisor-runc-static: $(SYSFS_PROTO_GO)
	cd $(RUNC_DIR) && make static

sysvisor-fs: $(SYSFS_SRC) $(SYSFS_PROTO_GO)
	go build -o sysvisor-fs/sysvisor-fs ./sysvisor-fs

sysvisor-fs-static: $(SYSFS_SRC) $(SYSFS_PROTO_GO)
	CGO_ENABLED=1 go build -tags "netgo osusergo static_build" -installsuffix netgo -ldflags "-w -extldflags -static" -o sysvisor-fs/sysvisor-fs ./sysvisor-fs

$(SYSFS_PROTO_GO): sysvisor-protobuf/sysvisor-protobuf.proto
	protoc -I sysvisor-protobuf/ -I /usr/local/include/ sysvisor-protobuf/sysvisor-protobuf.proto --go_out=plugins=grpc:sysvisor-protobuf

install:
	install -D -m0755 sysvisor-runc/sysvisor-runc $(BIN_DIR)/sysvisor-runc
	install -D -m0755 sysvisor-fs/sysvisor-fs $(BIN_DIR)/sysvisor-fs

uninstall:
	rm -f $(BIN_DIR)/sysvisor-runc
	rm -f $(BIN_DIR)/sysvisor-fs

# sysvisor-tests runs tests that verify sysvisor as a whole (i.e., sysvisor-runc + sysvisor-fs).
#
# NOTE: before running this target, see the requirements in file nestybox/sysvisor/tests/README
sysvisortest: all
	bats --tap tests${TESTPATH}

clean:
	cd $(GOPATH)/src/github.com/opencontainers/runc && make clean
	rm -f sysvisor-fs/sysvisor-fs
	rm -f $(SYSFS_PROTO_GO)
