# Makefile to build pivot-root.go

all: pivot-root-test

pivot-root-test: main.go
	GOOS=linux go build -buildvcs=false -ldflags "-extldflags -static" -o pivot-root-test

clean:
	rm pivot-root-test
