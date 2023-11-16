package main

import (
	"fmt"
	"os"
	"runtime"
	"syscall"
)

func main() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	fromPath := fmt.Sprintf("/proc/self/task/%d/ns/net", syscall.Gettid())
	toPath := "/tmp/test"

	f, err := os.Create(toPath)
	if err != nil {
		fmt.Printf("failed to create %s: %s\n", toPath, err)
		os.Exit(1)
	}
	f.Close()

	err = syscall.Mount(fromPath, toPath, "bind", syscall.MS_BIND, "")
	if err != nil {
		fmt.Printf("Error: failed to bind-mount %s -> %s: %s\n", fromPath, toPath, err)
		os.Exit(1)
	}

	fmt.Println("Pass!")
}
