package main

import (
	"log"
	"os"

	"golang.org/x/sys/unix"
)

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
	rootDir := "/"

	// Before unmounting "/", unmount all submounts; we expect these to fail with
	// "device or resource busy" or "operation not permitted", but we don't check
	// for errors since we later want to unmount "/".
	//
	// NOTE: These are the typical submounts inside a sysbox container
	submounts := []string{
		"/sys/firmware",
		"/sys/fs/cgroup",
		"/sys/devices/virtual",
		"/sys/devices/virtual/powercap",
		"/sys/kernel",
		"/sys/module/nf_conntrack/parameters",
		"/sys",

		"/proc/bus",
		"/proc/fs",
		"/proc/irq",
		"/proc/sysrq-trigger",
		"/proc/asound",
		"/proc/acpi",
		"/proc/keys",
		"/proc/timer_list",
		"/proc/scsi",
		"/proc/swaps",
		"/proc/sys",
		"/proc/uptime",
		"/proc",

		"/dev/mqueue",
		"/dev/pts",
		"/dev/shm",
		"/dev/null",
		"/dev/random",
		"/dev/kmsg",
		"/dev/full",
		"/dev/tty",
		"/dev/zero",
		"/dev/urandom",
		"/dev",

		"/etc/resolv.conf",
		"/etc/hostname",
		"/etc/hosts",

		"/usr/src/",

		"/var/lib/rancher/rke2",
		"/var/lib/kubelet",
		"/var/lib/k0s",
		"/var/lib/buildkit",
		"/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs",
		"/var/lib/docker",
		"/var/lib/rancher/k3s",
	}

	for _, m := range submounts {
		log.Printf("Unmounting %s\n", m)
		unix.Unmount(m, unix.MNT_FORCE)
	}

	log.Printf("Unmounting %s\n", rootDir)
	if err := unix.Unmount(rootDir, unix.MNT_FORCE); err == nil {
		log.Fatalf("Failed: unmount of / succeeded: %v", err)
	} else {
		log.Printf("Error (expected) while unmounting /: %v", err)
	}

	log.Println("Pass")
}
