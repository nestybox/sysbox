# Makefile to build xattr.go

all: xattr-test

xattr-test: xattr.go
	GOOS=linux go build -buildvcs=false -ldflags "-extldflags -static" -o xattr-test && chown "rootless:rootless" xattr-test

clean:
	rm xattr-test
