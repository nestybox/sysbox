# Makefile to build remount-fstype-spoof-test

.PHONY: all clean

all: remount-fstype-spoof-test

remount-fstype-spoof-test: main.go
	GOOS=linux go build -buildvcs=false -ldflags "-extldflags -static" -o remount-fstype-spoof-test main.go

clean:
	rm -f remount-fstype-spoof-test
