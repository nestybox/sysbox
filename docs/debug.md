Sysbox debugging notes
========================

## Debugging image

Before initiating a debugging session, we must ensure that the
binaries that we will be operating on have been built with
compiler-optimizations disabled. The following sysbox Makefile
targets have been created for this purpose:

```
sysbox-debug
sysbox-runc-debug
sysbox-fs-debug
sysbox-mgr-debug
```

Example:

```
$ make sysbox-debug && sudo make install
```

In some cases, it's desirable to debug process initialization phases,
so in those cases we must pick a convenient location where to place a
`sleep` instruction that provides user with enough time to launch the
debugger.

Example (sysbox-runc):

```
diff --git a/create.go b/create.go
index bb551950..a2b29beb 100644
--- a/create.go
+++ b/create.go
@@ -2,6 +2,7 @@ package main

 import (
        "os"
+       "time"

@@ -59,6 +60,7 @@ command(s) that get executed on start, edit the args parameter of the spec. See
                if err := revisePidFile(context); err != nil {
                        return err
                }
+               time.Sleep(time.Second * 30)
                if err := sysbox.CheckHostConfig(context); err != nil {
                        return err
                }

```

## Debugger instructions

Even though GDB offers Golang support, in reality there are a few key
features missing today, such as proper understanding of Golang's
concurrency constructs (e.g. goroutines). In consequence, in this
document i will be focusing on Delve debugger, which is not as
feature-rich as the regular GDB, but it fully supports Golang's
runtime. Luckily, most of the existing Delve instructions fully match
GDB ones, so i will mainly concentrate on those that (slightly)
deviate.

* Installation:

```
$ go get -u github.com/derekparker/delve/cmd/dlv
```

- Change working directory to the location that contains the source
  files of the the binary to debug:

```
rodny@deepblue-vm-1:~$ cd ~/go/src/github.com/nestybox/sysbox/sysbox-runc
```

* Attaching to a running process:

```
rodny@deepblue-vm-1:~/go/src/github.com/nestybox/sysbox/sysbox-runc$ sudo env "PATH=$PATH" env "GOROOT=$GOROOT" env "GOPATH=$GOPATH" env "PWD=$PWD" /home/rodny/go/bin/dlv attach 26558
```

Notice that to allow Golang runtime to operate as we expect, we must
export the existing Golang related env-vars to the newly-spawn delve
process.


* Setting break-points:

Depending on the level of granularity required, we can set breakpoints
attending to either one of these approches:

    - Package + Receiver + Method: (dlv) b libcontainer.(*initProcess).start
    - File + Line:                 (dlv) b process_linux.go:290

Example:

```
(dlv) b libcontainer.(*initProcess).start
Breakpoint 1 set at 0x55731c80152d for github.com/opencontainers/runc/libcontainer.(*initProcess).start() /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/process_linux.go:263
```

* Process iteration:

We can make use of the typical `n` (next), `s` (step), `c` (continue) instruccions to iterate through a process' instruction-set.

Example:

```
(dlv) c
> github.com/opencontainers/runc/libcontainer.(*initProcess).start() /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/process_linux.go:263 (hits goroutine(1):1 total:1) (PC: 0x55731c80152d)
   258:         p.cmd.Process = process
   259:         p.process.ops = p
   260:         return nil
   261: }
   262:
=> 263: func (p *initProcess) start() error {
   264:         defer p.parentPipe.Close()
   265:         err := p.cmd.Start()
   266:         p.process.ops = p
   267:         p.childPipe.Close()
   268:         if err != nil {
```

* Inspecting the stack-trace:

```
(dlv) bt
 0  0x000055731c80152d in github.com/opencontainers/runc/libcontainer.(*initProcess).start
    at /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/process_linux.go:263
 1  0x000055731c7dc2e2 in github.com/opencontainers/runc/libcontainer.(*linuxContainer).start
    at /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/container_linux.go:348
 2  0x000055731c7db749 in github.com/opencontainers/runc/libcontainer.(*linuxContainer).Start
    at /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/container_linux.go:249
 3  0x000055731c86a489 in main.(*runner).run
    at /home/rodny/go/src/github.com/opencontainers/runc/utils_linux.go:324
 4  0x000055731c86b7bc in main.startContainer
    at /home/rodny/go/src/github.com/opencontainers/runc/utils_linux.go:464
 5  0x000055731c86c0fd in main.glob..func2
    at /home/rodny/go/src/github.com/opencontainers/runc/create.go:75
 6  0x000055731c1c781d in runtime.call32
    at /usr/local/go/src/runtime/asm_amd64.s:522
 7  0x000055731c252006 in reflect.Value.call
    at /usr/local/go/src/reflect/value.go:447
 8  0x000055731c2512dc in reflect.Value.Call
    at /usr/local/go/src/reflect/value.go:308
 9  0x000055731c825433 in github.com/opencontainers/runc/vendor/github.com/urfave/cli.HandleAction
    at /home/rodny/go/src/github.com/opencontainers/runc/vendor/github.com/urfave/cli/app.go:487
10  0x000055731c826d2c in github.com/opencontainers/runc/vendor/github.com/urfave/cli.Command.Run
    at /home/rodny/go/src/github.com/opencontainers/runc/vendor/github.com/urfave/cli/command.go:191
11  0x000055731c822f27 in github.com/opencontainers/runc/vendor/github.com/urfave/cli.(*App).Run
    at /home/rodny/go/src/github.com/opencontainers/runc/vendor/github.com/urfave/cli/app.go:240
12  0x000055731c85f510 in main.main
    at /home/rodny/go/src/github.com/opencontainers/runc/main.go:194
13  0x000055731c19b699 in runtime.main
    at /usr/local/go/src/runtime/proc.go:201
14  0x000055731c1c9581 in runtime.goexit
    at /usr/local/go/src/runtime/asm_amd64.s:1333
(dlv)
```


* Inspecting POSIX threads:

```
(dlv) threads
  Thread 26558 at 0x55731c1cb403 /usr/local/go/src/runtime/sys_linux_amd64.s:532 runtime.futex
  Thread 26559 at 0x55731c1cae7d /usr/local/go/src/runtime/sys_linux_amd64.s:131 runtime.usleep
* Thread 26560 at 0x55731c80152d /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/process_linux.go:263 github.com/opencontainers/runc/libcontainer.(*initProcess).start
  Thread 26561 at 0x55731c1cb403 /usr/local/go/src/runtime/sys_linux_amd64.s:532 runtime.futex
  Thread 26562 at :0
  Thread 26575 at :0
(dlv)
```

* Inspecting goroutines:

```
(dlv) goroutines
* Goroutine 1 - User: /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/process_linux.go:263 github.com/opencontainers/runc/libcontainer.(*initProcess).start (0x55731c80152d) (thread 26560)
  Goroutine 2 - User: /usr/local/go/src/runtime/proc.go:303 runtime.gopark (0x55731c19ba76)
  Goroutine 3 - User: /usr/local/go/src/runtime/proc.go:303 runtime.gopark (0x55731c19ba76)
  Goroutine 4 - User: /usr/local/go/src/runtime/proc.go:303 runtime.gopark (0x55731c19ba76)
  Goroutine 6 - User: /usr/local/go/src/runtime/sigqueue.go:139 os/signal.signal_recv (0x55731c1b101e)
  Goroutine 7 - User: /usr/local/go/src/runtime/proc.go:303 runtime.gopark (0x55731c19ba76)
  Goroutine 20 - User: /usr/local/go/src/runtime/proc.go:303 runtime.gopark (0x55731c19ba76)
[7 goroutines]
(dlv)
```

* Printing:

There's nothing new here, just use the regular `p` (print) instruction. But keep in mind this instruction when trying to print long strings in the debugger, as by default only 64 characters are displayed. This instruction extends that limit to any other value:

```
(dlv) config max-string-len 1000
```


## Useful Debugger Options

Configure print length of strings:

```
(dlv) config max-string-len 1000
```


## Debugging CGO code

To debug cgo code, you must use gdb (delve does not work).

Instructions:

1) Build the cgo code with "go build --buildmode=exe"; do not use "--buildmode=pie", as the position independent code confuses gdb.

   - There may be a gdb option/command to get around this, but it's easier to just build with "--buildmode=exe" during debug.

2) In the golang file that calls cgo, use the "-g" switch, to tell gccgo to generate debug symbols.

```
#cgo CFLAGS: -Wall -g
```

3) If needed, instrument the binary to allow you time to attach the
   debugger to it.

   - For example, to attach to the sysbox-runc nsenter child process
     which is normally ephemeral, add an debug "sleep()" to an
     appropriate location within the nsenter (to give you time to find
     the nsenter pid and attach the debugger to it), then execute
     sysbox-runc, find the pid with pstree, and attach gdb to it (next step).

3) Attach gdb to the target process:

```
root@eoan:/mnt/dev-ws/cesar/nestybox/sysbox# gdb --pid 17089

GNU gdb (Ubuntu 8.3-0ubuntu1) 8.3
Copyright (C) 2019 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
Type "show copying" and "show warranty" for details.
This GDB was configured as "x86_64-linux-gnu".
Type "show configuration" for configuration details.
For bug reporting instructions, please see:
<http://www.gnu.org/software/gdb/bugs/>.
Find the GDB manual and other documentation resources online at:
    <http://www.gnu.org/software/gdb/documentation/>.

For help, type "help".
Type "apropos word" to search for commands related to "word".
Attaching to process 17089
No executable file now.

warning: Could not load vsyscall page because no executable was specified
0x00007f0d78abf2e2 in ?? ()
```

4) Point gdb to the sysbox-runc binary so it can load the symbols:

```
(gdb) file /usr/local/sbin/sysbox-runc
A program is being debugged already.
Are you sure you want to change the file? (y or n) y
Reading symbols from /usr/local/sbin/sysbox-runc...
Loading Go Runtime support.

(gdb) bt
#0  0x00007f0d78abf2e2 in ?? ()
#1  0x0000000000bb4b23 in read (__nbytes=16, __buf=0x7fff3fcba260, __fd=4) at /usr/include/x86_64-linux-gnu/bits/unistd.h:44
#2  nl_parse (config=0x7fff3fcba270, fd=4) at nsexec.c:422
#3  nsexec () at nsexec.c:634
#4  0x0000000000bc3fbd in __libc_csu_init ()
#5  0x00007f0d788db16e in ?? ()
#6  0x0000000000000000 in ?? ()
```

5) Then use gdb as usual:

```
(gdb) break nsexec.c:650
Breakpoint 1 at 0xbb4f68: file nsexec.c, line 650.
(gdb) c
Continuing.

Breakpoint 1, update_oom_score_adj (len=4, data=0xe2f62e "-999") at nsexec.c:650
650        update_oom_score_adj("-999", 4);

(gdb) n
nsexec () at nsexec.c:662
662             if (config.namespaces) {
    (gdb) p config
    $1 = {data = 0x1b552a0 "\b", cloneflags = 2114060288, oom_score_adj = 0x1b552dc "0", oom_score_adj_len = 2, uidmap = 0x1b552ac "0 165536 65536\n", uidmap_len = 16, gidmap = 0x1b552c0 "0 165536 65536\n", gidmap_len = 16, namespaces = 0x0, namespaces_len = 0, is_setgroup = 1 '\001', is_rootless_euid = 0 '\000',
uidmappath = 0x0, uidmappath_len = 0, gidmappath = 0x0, gidmappath_len = 0, prep_rootfs = 1 '\001', use_shiftfs = 1 '\001', make_parent_priv = 0 '\000', rootfs_prop = 540672, rootfs = 0x1b5530c "/var/lib/docker/overlay2/d764bae04e3e81674c0f0c8ccfc8dec1ef2483393027723bac6519133fa7a4a2/merged", rootfs_len = 97,
parent_mount = 0x0, parent_mount_len = 0, shiftfs_mounts = 0x1b55374 "/lib/modules/5.3.0-46-generic,/usr/src/linux-headers-5.3.0-46,/usr/src/linux-headers-5.3.0-46-generic,/var/lib/docker/containers/cbf6dfe2bef0563532770ed664829032d00eb278367176de32cd03b7290ea1ac", shiftfs_mounts_len = 194}

(gdb) set print pretty
(gdb) p config
$2 = {
data = 0x1b552a0 "\b",
cloneflags = 2114060288,
oom_score_adj = 0x1b552dc "0",
oom_score_adj_len = 2,
uidmap = 0x1b552ac "0 165536 65536\n",
uidmap_len = 16,
gidmap = 0x1b552c0 "0 165536 65536\n",
gidmap_len = 16,
namespaces = 0x0,
namespaces_len = 0,
is_setgroup = 1 '\001',
is_rootless_euid = 0 '\000',
uidmappath = 0x0,
uidmappath_len = 0,
gidmappath = 0x0,
gidmappath_len = 0,
prep_rootfs = 1 '\001',
--Type <RET> for more, q to quit, c to continue without paging--q
Quit
```

Tip: if you are running sysbox-runc inside the test container, run gdb at host level,
use pstree to figure out the pid of sysbox-runc nsenter child process inside the test container,
and point gdb to the sysbox-runc binary inside the test container (e.g.,
`file /var/lib/docker/overlay2/860f62b3bd74c36be6754c8ed8e3f77a63744a2c6b16bef058b22ba0185e2877/merged/usr/local/sbin/sysbox-runc`).
