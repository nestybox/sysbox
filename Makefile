.PHONY: all sysvisor sysvisor-runc sysvisor-fs

SYSFS_PROTO_GO=sysvisor-protobuf/sysvisor_protobuf.pb.go

.DEFAULT: sysvisor

sysvisor: $(SYSFS_PROTO_GO) sysvisor-runc sysvisor-fs

sysvisor-runc:
	cd $(GOPATH)/src/github.com/opencontainers/runc && make

sysvisor-fs:
	go build -o sysvisor-fs/sysvisor-fs ./sysvisor-fs

$(SYSFS_PROTO_GO): sysvisor-protobuf/sysvisor_protobuf.proto
	protoc -I sysvisor-protobuf/ -I /usr/local/include/ sysvisor-protobuf/sysvisor_protobuf.proto --go_out=plugins=grpc:sysvisor-protobuf

all: sysvisor

clean:
	cd $(GOPATH)/src/github.com/opencontainers/runc && make clean
	rm -f sysvisor-fs/sysvisor-fs
	rm -f $(SYSFS_PROTO_GO)
