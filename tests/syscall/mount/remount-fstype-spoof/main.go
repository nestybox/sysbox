package main

import (
	"flag"
	"fmt"
	"os"
	"unsafe"

	"golang.org/x/sys/unix"
)

// This program issues a raw mount(2) syscall of the form:
//
//	mount(NULL, <target>, <fstype>, MS_REMOUNT|MS_BIND, NULL)
//
// It exists to reproduce (and guard against regressions of) a sysbox-fs
// mount(2) mediation bypass: for MS_REMOUNT, the kernel ignores the
// "source" and "filesystemtype" arguments entirely (see
// mount(2)), yet sysbox-fs used the tracee-supplied "fstype" to decide
// whether a remount targeted procfs/sysfs (and could thus skip its
// immutable read-only mount checks). A caller could pass fstype="proc"
// while actually targeting an unrelated read-only immutable mount (e.g.
// the default /lib/modules/<kernel> bind mount) to flip it read-write.
//
// The "-fstype" flag is passed through as-is, except for the literal
// value "NULL", which this program turns into a genuine NULL pointer
// (as opposed to a pointer to an empty string) -- Go's higher-level mount
// wrappers (syscall.Mount, golang.org/x/sys/unix.Mount) can't express
// that distinction, but it matters here: a NULL fstype is the negative
// control that proves the bypass is caused specifically by the
// proc/sysfs spoof, and not by some broader failure of the immutable-
// mount protection.
func main() {
	fstypeFlag := flag.String("fstype", "NULL",
		`Filesystem type to pass to mount(2). Use "NULL" (the default) to pass a`+
			` genuine NULL pointer instead of a filesystem-type string.`)
	verbose := flag.Bool("v", false, "Print the mount(2) call before issuing it.")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s [options] <target>\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "\nIssues mount(NULL, target, fstype, MS_REMOUNT|MS_BIND, NULL).\n")
		fmt.Fprintf(os.Stderr, "\nOptions:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NArg() != 1 {
		flag.Usage()
		os.Exit(2)
	}
	target := flag.Arg(0)

	// Resolve the target into a byte pointer; this argument is always a
	// real string, since MS_REMOUNT always requires a target.
	targetPtr, err := unix.BytePtrFromString(target)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid target %q: %v\n", target, err)
		os.Exit(2)
	}

	// Resolve the fstype into a byte pointer, or leave it nil (i.e., a
	// NULL pointer at the syscall level) when "-fstype NULL" is given.
	var fstypePtr *byte
	if *fstypeFlag != "NULL" {
		fstypePtr, err = unix.BytePtrFromString(*fstypeFlag)
		if err != nil {
			fmt.Fprintf(os.Stderr, "invalid fstype %q: %v\n", *fstypeFlag, err)
			os.Exit(2)
		}
	}

	if *verbose {
		fmt.Printf("mount(NULL, %q, %q, MS_REMOUNT|MS_BIND, NULL)\n", target, *fstypeFlag)
	}

	_, _, errno := unix.Syscall6(
		unix.SYS_MOUNT,
		0, // source
		uintptr(unsafe.Pointer(targetPtr)),
		uintptr(unsafe.Pointer(fstypePtr)),
		uintptr(unix.MS_REMOUNT|unix.MS_BIND),
		0, // data
		0,
	)
	if errno != 0 {
		fmt.Fprintf(os.Stderr, "mount: %s\n", errno.Error())
		os.Exit(1)
	}

	fmt.Println("mount succeeded")
}
