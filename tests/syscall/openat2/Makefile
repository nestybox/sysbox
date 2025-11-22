# Makefile to build openat2-test

.PHONY: all openat2-test

all: openat2-test

openat2-test:
	GOOS=linux go build -buildvcs=false -ldflags "-extldflags -static" -o openat2-test openat2.go

clean:
	rm openat2-test
