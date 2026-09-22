package main

import (
	"flag"
	"fmt"
	"os"

	"golang.org/x/sys/unix"
)

// This program attempts to clear the read-only attribute (MOUNT_ATTR_RDONLY)
// of a given mount via the modern mount API (mount_setattr(2), and
// optionally open_tree(2) + move_mount(2)), rather than the legacy mount(2)
// MS_REMOUNT interface. It exists to verify that sysbox's immutable
// kernel-header and kernel-module mounts (/usr/src/*,
// /lib/modules/<kernel>) can't be made read-write via this newer API
// surface, which sysbox-fs does not mediate.
//
// By default, it calls mount_setattr(2) directly on the given target:
//
//	mount_setattr(AT_FDCWD, <target>, 0, {attr_clr: MOUNT_ATTR_RDONLY})
//
// With "-clone-to", it instead models an attacker trying to sidestep an
// in-place modification by operating on a *detached clone* of the target
// (obtained via open_tree(2)'s OPEN_TREE_CLONE flag) and then attaching
// that clone elsewhere via move_mount(2):
//
//	fd := open_tree(<target>, OPEN_TREE_CLONE|AT_RECURSIVE)
//	mount_setattr(fd, "", AT_EMPTY_PATH, {attr_clr: MOUNT_ATTR_RDONLY})
//	move_mount(fd, "", AT_FDCWD, <clone-to>, MOVE_MOUNT_F_EMPTY_PATH)
//
// Exit code 0 means the read-only attribute was actually cleared (i.e., the
// immutable-mount protection was bypassed). Any other exit code means the
// protection held; a diagnostic identifying which step failed is printed to
// stderr.
func main() {
	cloneTo := flag.String("clone-to", "",
		"Operate on a detached open_tree(2) clone of <target> and attach it"+
			" here via move_mount(2), instead of calling mount_setattr(2)"+
			" directly on <target>.")
	verbose := flag.Bool("v", false, "Print each syscall issued.")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s [options] <target>\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "\nAttempts to clear MOUNT_ATTR_RDONLY on <target> via mount_setattr(2).\n")
		fmt.Fprintf(os.Stderr, "\nOptions:\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NArg() != 1 {
		flag.Usage()
		os.Exit(2)
	}
	target := flag.Arg(0)

	if *cloneTo == "" {
		clearReadOnly(unix.AT_FDCWD, target, 0, *verbose)
		return
	}

	// "-clone-to": detach a clone of target, try to clear its read-only
	// attribute, then attach the (possibly still read-only) clone at
	// <clone-to> so the caller can independently verify its state.
	if *verbose {
		fmt.Printf("open_tree(%q, OPEN_TREE_CLONE|OPEN_TREE_CLOEXEC|AT_RECURSIVE)\n", target)
	}

	fd, err := unix.OpenTree(unix.AT_FDCWD, target,
		unix.OPEN_TREE_CLONE|unix.OPEN_TREE_CLOEXEC|unix.AT_RECURSIVE)
	if err != nil {
		fmt.Fprintf(os.Stderr, "open_tree: %s\n", err)
		os.Exit(2)
	}
	defer unix.Close(fd)

	clearReadOnly(fd, "", unix.AT_EMPTY_PATH, *verbose)

	if *verbose {
		fmt.Printf("move_mount(clone, \"\", AT_FDCWD, %q, MOVE_MOUNT_F_EMPTY_PATH)\n", *cloneTo)
	}

	if err := unix.MoveMount(fd, "", unix.AT_FDCWD, *cloneTo, unix.MOVE_MOUNT_F_EMPTY_PATH); err != nil {
		fmt.Fprintf(os.Stderr, "move_mount: %s\n", err)
		os.Exit(2)
	}
}

// clearReadOnly issues mount_setattr(dirfd, pathname, flags, {attr_clr:
// MOUNT_ATTR_RDONLY}), reports the outcome, and exits the program: 0 if the
// read-only attribute was cleared, 1 if the kernel rejected the attempt.
func clearReadOnly(dirfd int, pathname string, flags uint, verbose bool) {
	attr := &unix.MountAttr{
		Attr_clr: unix.MOUNT_ATTR_RDONLY,
	}

	if verbose {
		fmt.Printf("mount_setattr(%d, %q, %d, {attr_clr: MOUNT_ATTR_RDONLY})\n",
			dirfd, pathname, flags)
	}

	if err := unix.MountSetattr(dirfd, pathname, flags, attr); err != nil {
		fmt.Fprintf(os.Stderr, "mount_setattr: %s\n", err)
		os.Exit(1)
	}

	fmt.Println("mount_setattr succeeded")
}
