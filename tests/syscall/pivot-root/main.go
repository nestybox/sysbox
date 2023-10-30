package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/moby/sys/mount"
	"github.com/moby/sys/mountinfo"
	"golang.org/x/sys/unix"
)

// SwitchRoot changes path to be the root of the mount tree and changes the
// current working directory to the new root. Returns the path to the old root
// from within the new root. The caller can unmount the old root if needed.
//
// NOTE: code adapted from "github.com/docker/docker/internal/mounttree"
func SwitchRoot(path string) (string, error) {
	if mounted, _ := mountinfo.Mounted(path); !mounted {
		if err := mount.Mount(path, path, "bind", "rbind,rw"); err != nil {
			return "", fmt.Errorf("Failed to bind mount %s: %s", path, err)
		}
	}

	// setup oldRoot for pivot_root
	pivotDir, err := os.MkdirTemp(path, "old_root")
	if err != nil {
		return "", fmt.Errorf("Error setting up pivot dir: %v", err)
	}

	if err := unix.PivotRoot(path, pivotDir); err != nil {
		return "", fmt.Errorf("pivot-root failed: %s", err)
	}

	// This is the new path for where the old root (prior to the pivot) has been
	// moved to This dir contains the rootfs of the caller, which we need to
	// remove so it is not visible during extraction
	pivotDir = filepath.Join("/", filepath.Base(pivotDir))

	if err := unix.Chdir("/"); err != nil {
		return "", fmt.Errorf("Error changing to new root: %v", err)
	}

	return pivotDir, nil
}

func listDir(path string) error {
	log.Printf("Files under %s:\n", path)
	files, err := os.ReadDir(path)
	if err != nil {
		return err
	}
	for _, file := range files {
		log.Println(file.Name())
	}
	return nil
}

func main() {
	newRoot := "new_root"
	err := os.MkdirAll(newRoot, 0750)
	if err != nil {
		log.Fatal(err)
	}

	data := []byte("hello world\n")
	err = os.WriteFile(filepath.Join(newRoot, "testfile"), data, 0644)

	// Switch this process' root
	oldRoot, err := SwitchRoot(newRoot)
	if err != nil {
		log.Fatalf("failed to switch root to %s: %s", newRoot, err)
	}

	log.Printf("Switched root to %s\n", newRoot)

	// Verify
	cwd, err := os.Getwd()
	if err != nil {
		log.Fatalf("Failed: error while getting current dir: %s", err)
	}
	log.Printf("Current dir = %s\n", cwd)
	log.Printf("Files under new root:\n")

	if err := listDir("/"); err != nil {
		log.Fatal(err)
	}

	// List files under old root
	if err := listDir(oldRoot); err != nil {
		log.Fatal(err)
	}

	// Umount old root
	log.Printf("Unmounting %s\n", oldRoot)
	if err := unix.Mount("", oldRoot, "", unix.MS_PRIVATE|unix.MS_REC, ""); err != nil {
		log.Fatalf("Failed: error making old root private after pivot: %v", err)
	}
	if err := unix.Unmount(oldRoot, unix.MNT_DETACH); err != nil {
		log.Fatalf("Failed: error while unmounting old root after pivot: %v", err)
	}

	log.Println("Pass.")
}
