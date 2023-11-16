all: proc-self-mount-test

proc-self-mount-test: main.go
	GOOS=linux go build -buildvcs=false -ldflags "-extldflags -static" -o proc-self-mount-test

clean:
	rm -f proc-self-mount-test
