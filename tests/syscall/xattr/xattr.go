//
// Copyright 2021 Nestybox, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

// This file contains tests to verify Sysbox processing of l*xattr() and
// f*xattr() syscalls (i.e., the link-based and fd-based variants of the
// *xattr() syscalls. This file complements the xattr.bats file which uses the
// setfattr and getfattr utilities to test the *xattr() functions. Unfortunately
// these utilities don't allow control over using the l*xattr() and f*xattr()
// syscall variants, thus the need for this file.

package main

import (
	"os"
	"fmt"
	"golang.org/x/sys/unix"
)

// Verify the f*xattr() syscalls
func testFxattr(tfile string) error {
	var (
		f *os.File
		size int
		err error
	)

	f, err = os.Create(tfile)
	if err != nil {
		return err
	}
	defer f.Close()

	fd := int(f.Fd())

	err = unix.Fsetxattr(fd, "trusted.overlay.opaque", []byte{'y'}, 0)
	if err != nil {
		return fmt.Errorf("fsetxattr() failed: %s", err)
	}

	// This will cause fgetxattr() to return the size of the buffer required to hold the xattr value
	size, err = unix.Fgetxattr(fd, "trusted.overlay.opaque", []byte{})
	if err != nil {
		return fmt.Errorf("fgetxattr() failed: %s", err)
	}

	if size != 1 {
		return fmt.Errorf("fgetxattr() got unexpected size: want 1, got %d", size)
	}

	// Now that we know the size, let's retrieve the xattr value itself
	buf := make([]byte, size)

	size, err = unix.Fgetxattr(fd, "trusted.overlay.opaque", buf)
	if err != nil {
		return fmt.Errorf("fgetxattr() failed: %s", err)
	}

	if len(buf) != 1 || buf[0] != 'y' || size != len(buf) {
		return fmt.Errorf("fgetxattr() got unexpected attr: %s", string(buf))
	}

	// Test flistxattr()
	size, err = unix.Flistxattr(fd, []byte{})
	if err != nil {
		return fmt.Errorf("flistxattr() failed: %s", err)
	}

	buf = make([]byte, size)

	size, err = unix.Flistxattr(fd, buf)
	if err != nil {
		return fmt.Errorf("flistxattr() failed: %s", err)
	}

	if len(buf) != size || string(buf) != "trusted.overlay.opaque\x00" {
		return fmt.Errorf("flistxattr() got unexpected attr: %v %s", string(buf))
	}

	err = unix.Fremovexattr(fd, "trusted.overlay.opaque")
	if err != nil {
		return fmt.Errorf("fremovexattr() failed: %s", err)
	}

	size, err = unix.Fgetxattr(fd, "trusted.overlay.opaque", buf)
	if err == nil {
		return fmt.Errorf("fgetxattr() expected to failed but passed")
	}

	return nil
}

// Verify the l*xattr() syscalls
func testLxattr(tfile string) error {
	var (
		f *os.File
		size int
		err error
	)

	// create a test file
	f, err = os.Create(tfile)
	if err != nil {
		return err
	}
	f.Close()

	tlink := "/mnt/tdir/tlink"

	// create a symlink to the test file
	err = os.Symlink(tfile, tlink)
	if err != nil {
		return fmt.Errorf("failed to create symlink to %s: %s", tfile, err)
	}

	// Set the xattr on the link itself
	err = unix.Lsetxattr(tlink, "trusted.overlay.opaque", []byte{'y'}, 0)
	if err != nil {
		return fmt.Errorf("lsetxattr() failed: %s", err)
	}

	// This will cause lgetxattr() to return the size of the buffer required to hold the xattr value
	size, err = unix.Lgetxattr(tlink, "trusted.overlay.opaque", []byte{})
	if err != nil {
		return fmt.Errorf("lgetxattr() failed: %s", err)
	}

	if size != 1 {
		return fmt.Errorf("lgetxattr() got unexpected size: want 1, got %d", size)
	}

	// Now that we know the size, let's retrieve the xattr value itself
	buf := make([]byte, size)

	size, err = unix.Lgetxattr(tlink, "trusted.overlay.opaque", buf)
	if err != nil {
		return fmt.Errorf("lgetxattr() failed: %s", err)
	}

	if len(buf) != 1 || buf[0] != 'y' || size != len(buf) {
		return fmt.Errorf("lgetxattr() got unexpected attr: %s", string(buf))
	}

	// Test flistxattr()
	size, err = unix.Llistxattr(tlink, []byte{})
	if err != nil {
		return fmt.Errorf("llistxattr() failed: %s", err)
	}

	buf = make([]byte, size)

	size, err = unix.Llistxattr(tlink, buf)
	if err != nil {
		return fmt.Errorf("llistxattr() failed: %s", err)
	}

	if len(buf) != size || string(buf) != "trusted.overlay.opaque\x00" {
		return fmt.Errorf("llistxattr() got unexpected attr: %v %s", string(buf))
	}

	err = unix.Lremovexattr(tlink, "trusted.overlay.opaque")
	if err != nil {
		return fmt.Errorf("lremovexattr() failed: %s", err)
	}

	size, err = unix.Lgetxattr(tlink, "trusted.overlay.opaque", buf)
	if err == nil {
		return fmt.Errorf("lgetxattr() expected to failed but passed")
	}

	return nil
}

// Verifies the 'flags' parameter of *setxattr() syscalls works as expected
func testXattrFlags(tfile string) error {
	var (
		f *os.File
		size int
		err error
	)

	f, err = os.Create(tfile)
	if err != nil {
		return err
	}
	defer f.Close()

	fd := int(f.Fd())

	err = unix.Fsetxattr(fd, "trusted.overlay.opaque", []byte{'y'}, unix.XATTR_CREATE)
	if err != nil {
		return fmt.Errorf("fsetxattr(XATTR_CREATE) failed: %s", err)
	}

	err = unix.Fsetxattr(fd, "trusted.overlay.opaque", []byte{'y'}, unix.XATTR_CREATE)
	if err == nil {
		return fmt.Errorf("fsetxattr() with XATTR_CREATE passed but was expected to fail")
	}

	err = unix.Fsetxattr(fd, "trusted.overlay.opaque", []byte{'n'}, unix.XATTR_REPLACE)
	if err != nil {
		return fmt.Errorf("fsetxattr(XATTR_REPLACE) failed: %s", err)
	}

	// Verify the XATTR_REPLACE worked
	buf := make([]byte, 1)

	size, err = unix.Fgetxattr(fd, "trusted.overlay.opaque", buf)
	if err != nil {
		return fmt.Errorf("fgetxattr() failed: %s", err)
	}

	if len(buf) != 1 || buf[0] != 'n' || size != len(buf) {
		return fmt.Errorf("fgetxattr() got unexpected attr: %s", string(buf))
	}

	return nil
}

func main() {

	if len(os.Args) != 2 {
		fmt.Printf("Usage: %s <test_file>\n", os.Args[0])
		os.Exit(1)
	}

	tfile := os.Args[1]

	if err := testFxattr(tfile); err != nil {
		fmt.Printf("Test failure: %s\n", err)
		os.Exit(1)
	}

	if err := testLxattr(tfile); err != nil {
		fmt.Printf("Test failure: %s\n", err)
		os.Exit(1)
	}

	if err := testXattrFlags(tfile); err != nil {
		fmt.Printf("Test failure: %s\n", err)
		os.Exit(1)
	}

	os.Exit(0)
}
