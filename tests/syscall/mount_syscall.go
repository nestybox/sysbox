package main

import (
	"fmt"
	"log"
	"os"

	"golang.org/x/sys/unix"
)

func do_bind_mount(s, t string) {

	err := unix.Mount(s, t, "", unix.MS_BIND, "")
	if err != nil {
		fmt.Printf("bind-mount error received %v:", err)
	}
}

func do_remount_ro(s, t string) {

	err := unix.Mount(s, t, "", unix.MS_BIND|unix.MS_REMOUNT|unix.MS_RDONLY, "")
	if err != nil {
		fmt.Printf("RO remount error received %v:", err)
	}
}

func do_remount_rw(s, t string) {

	err := unix.Mount(s, t, "", unix.MS_BIND|unix.MS_REMOUNT, "")
	if err != nil {
		fmt.Printf("RW remount error received: %v", err)
	}
}

func usage() {
	fmt.Printf("\nUsage: mount_syscall <bind | ro-remount | rw-remount> <source> <target>\n\n")
}

func main() {
	args := os.Args[1:]

	if len(args) != 3 {
		fmt.Printf("\nNumber of attributes received: %d, expected: %d\n", len(args), 3)
		usage()
		os.Exit(1)
	}

	if args[0] == "bind" {
		do_bind_mount(args[1], args[2])
	} else if args[0] == "ro-remount" {
		do_remount_ro(args[1], args[2])
	} else if args[0] == "rw-remount" {
		do_remount_rw(args[1], args[2])
	} else {
		log.Printf("Unsupported option: %s", args[0])
	}
}
