#!/bin/bash -e
#
# Script to run sysbox integration testcases for syscall-interception
# feature.
#

progName=$(basename "$0")

# Argument testName is optional
if [ $# -eq 1 ]; then
  printf "\nExecuting $1 ... \n"
  bats --tap $1
  return
fi

printf "\nExecuting chown syscall tests ... \n"
bats --tap tests/syscall/chown

printf "\nExecuting clone syscall tests ... \n"
bats --tap tests/syscall/clone

printf "\nExecuting xattr syscall tests ... \n"
bats --tap tests/syscall/xattr

printf "\nExecuting basic mount syscall-interception tests ... \n"
bats --tap tests/syscall/mount/mount.bats

printf "\nExecuting mount syscall-interception tests for overlayfs resources ... \n"
bats --tap tests/syscall/mount/mount-overlayfs.bats

printf "\nExecuting mount syscall-interception tests for procfs resources ... \n"
bats --tap tests/syscall/mount/mount-procfs.bats

printf "\nExecuting mount syscall-interception tests for sysfs resources ... \n"
bats --tap tests/syscall/mount/mount-sysfs.bats

printf "\nExecuting mount syscall-interception tests for immutable resources ... \n"
bats --tap tests/syscall/mount/mount-immutables.bats

printf "\nExecuting mount syscall-interception tests for immutable resources in chroot() ctx ... \n"
bats --tap tests/syscall/mount/mount-immutables-chroot.bats

printf "\nExecuting mount syscall-interception tests for immutable resources in unshare() ctx ... \n"
bats --tap tests/syscall/mount/mount-immutables-unshare.bats

printf "\nExecuting mount syscall-interception tests for immutable resources in unshare() + chroot() ctx ... \n"
bats --tap tests/syscall/mount/mount-immutables-unshare-chroot.bats

printf "\nExecuting mount syscall-interception tests for immutable resources in unshare() + pivot() ctx ... \n"
bats --tap tests/syscall/mount/mount-immutables-unshare-pivot.bats

printf "\nExecuting mount syscall-interception tests using /proc/self/* paths ... \n"
bats --tap tests/syscall/mount/proc-self-mount/proc-self-mount.bats

printf "\nExecuting pivot-root tests ... \n"
bats --tap tests/syscall/pivot-root

printf "\nExecuting umount-root tests ... \n"
bats --tap tests/syscall/umount-root
