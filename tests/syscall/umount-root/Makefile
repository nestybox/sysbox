# Makefile to build umount-root.go

all: umount-root-test

umount-root-test: main.go
	GOOS=linux go build -buildvcs=false -ldflags "-extldflags -static" -o umount-root-test

clean:
	rm umount-root-test
