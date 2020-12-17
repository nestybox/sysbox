package main

import (
	"fmt"
	"os"

	"golang.org/x/sys/unix"
)

func do_bind_mount(s, t string) error {

	err := unix.Mount(s, t, "", unix.MS_BIND, "")
	if err != nil {
		fmt.Printf("bind-mount error received: %v\n", err)
		return err
	}

	return nil
}

func do_remount_ro(s, t string) error {

	err := unix.Mount(s, t, "", unix.MS_BIND|unix.MS_REMOUNT|unix.MS_RDONLY, "")
	if err != nil {
		fmt.Printf("RO remount error received: %v\n", err)
		return err
	}

	return nil
}

func do_remount_rw(s, t string) error {

	err := unix.Mount(s, t, "", unix.MS_BIND|unix.MS_REMOUNT, "")
	if err != nil {
		fmt.Printf("RW remount error received: %v\n", err)
		return err
	}

	return nil
}

func usage() {
	fmt.Printf("\nUsage: mount_syscall <bind | ro-remount | rw-remount> <source> <target>\n\n")
}

func main() {
	args := os.Args[1:]

	if len(args) != 3 {
		fmt.Printf("\nNumber of arguments received: %d, expected: %d\n", len(args), 3)
		usage()
		os.Exit(1)
	}

	var err error

	if args[0] == "bind" {
		err = do_bind_mount(args[1], args[2])
	} else if args[0] == "ro-remount" {
		err = do_remount_ro(args[1], args[2])
	} else if args[0] == "rw-remount" {
		err = do_remount_rw(args[1], args[2])
	} else {
		fmt.Printf("Unsupported command option: %s\n", args[0])
		err = fmt.Errorf("Unsupported command option: %s", args[0])
	}

	if err != nil {
		os.Exit(1)
	}
}
