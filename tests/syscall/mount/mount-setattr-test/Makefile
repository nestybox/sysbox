# Makefile to build mount-setattr-test

.PHONY: all clean

all: mount-setattr-test

mount-setattr-test: main.go
	GOOS=linux go build -buildvcs=false -ldflags "-extldflags -static" -o mount-setattr-test main.go

clean:
	rm -f mount-setattr-test
