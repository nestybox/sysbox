# Sysbox Developer's Guide: Debugging

This document provides tips on how to debug Sysbox.

## Contents

-   [Debug Makefile Targets](#debug-makefile-targets)
-   [Debugger instructions](#debugger-instructions)
-   [Useful Debugger Options](#useful-debugger-options)
-   [Debugging CGO code](#debugging-cgo-code)

## Debug Makefile Targets

Before initiating a debugging session, we must ensure that the binaries that we
will be operating on have been built with compiler-optimizations disabled. The
following sysbox Makefile targets have been created for this purpose:

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

In some cases, it's desirable to debug process initialization phases, so in
those cases we must pick a convenient location where to place a `sleep`
instruction that provides user with enough time to launch the debugger.

Example (sysbox-runc):

```diff
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

## Delve Debugger Instructions

Even though GDB offers Golang support, in reality there are a few key features
missing today, such as proper understanding of Golang's concurrency constructs
(e.g. goroutines). In consequence, in this document i will be focusing on Delve
debugger, which is not as feature-rich as the regular GDB, but it fully supports
Golang's runtime. Luckily, most of the existing Delve instructions fully match
GDB ones, so I will mainly concentrate on those that (slightly) deviate.

-   Installation:

    ```console
    rodny@vm-1:~$ go get -u github.com/derekparker/delve/cmd/dlv
    ```

-   Change working directory to the sysbox workspace location:

    ```console
    rodny@vm-1:~$ cd ~/wsp/sysbox
    ```

-   Attaching to a running process:

    Let's pick sysbox-runc as an example. First, we need to find the PID of the
    running sysbox-runc process. Use `pstree -SlpgT | grep sysbox` or
    `ps -ef | grep sysbox` to help with this.

    Then start the debugger and attach it to the sysbox-runc process via the PID:

    ```console
    rodny@vm-1:~/wsp/sysbox/sysbox$ sudo env "PATH=$PATH" env "GOROOT=$GOROOT" env "GOPATH=$GOPATH" env "PWD=$PWD" /home/rodny/go/bin/dlv attach 26558
    ```

    Notice that to allow Golang runtime to operate as we expect, we must
    export the existing Golang related env-vars to the newly-spawn delve
    process.

-   Delve command reference:

    https://github.com/go-delve/delve/blob/master/Documentation/cli/README.md

-   Setting break-points:

    Depending on the level of granularity required, we can set breakpoints
    attending to either one of these approches:

    - Package + Receiver + Method: (dlv) b libcontainer.(*initProcess).start
    - File + Line:                 (dlv) b process_linux.go:290

    Example:

    ```console
    (dlv) b libcontainer.(*initProcess).start
    Breakpoint 1 set at 0x55731c80152d for github.com/opencontainers/runc/libcontainer.(*initProcess).start() /home/rodny/go/src/github.com/opencontainers/runc/libcontainer/process_linux.go:263
    ```

-   Process iteration:

    We can make use of the typical `n` (next), `s` (step), `c` (continue) instruccions to iterate through a process' instruction-set.

    Example:

    ```console
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

-   Inspecting the stack-trace:

    ```console
    (dlv) bt
     0  0x00000000004ead9a in syscall.Syscall6
        at /usr/local/go/src/syscall/asm_linux_amd64.s:53
     1  0x0000000000524f55 in os.(*Process).blockUntilWaitable
        at /usr/local/go/src/os/wait_waitid.go:31
     2  0x00000000005194ae in os.(*Process).wait
        at /usr/local/go/src/os/exec_unix.go:22
     3  0x00000000005180a1 in os.(*Process).Wait
        at /usr/local/go/src/os/exec.go:125
     4  0x00000000007d870f in os/exec.(*Cmd).Wait
        at /usr/local/go/src/os/exec/exec.go:501
     5  0x0000000000d6c2fa in github.com/opencontainers/runc/libcontainer.  (*initProcess).wait
        at /root/nestybox/sysbox/sysbox-runc/libcontainer/process_linux.go:655
     6  0x0000000000d6c43f in github.com/opencontainers/runc/libcontainer.(*initProcess).terminate
        at /root/nestybox/sysbox/sysbox-runc/libcontainer/process_linux.go:668
     7  0x0000000000d89f35 in github.com/opencontainers/runc/libcontainer.(*initProcess).start.func1
        at /root/nestybox/sysbox/sysbox-runc/libcontainer/process_linux.go:353
     8  0x0000000000d6bace in github.com/opencontainers/runc/libcontainer.(*initProcess).start
        at /root/nestybox/sysbox/sysbox-runc/libcontainer/process_linux.go:592
     9  0x0000000000d3f3ae in github.com/opencontainers/runc/libcontainer.(*linuxContainer).start
        at /root/nestybox/sysbox/sysbox-runc/libcontainer/container_linux.go:390
    10  0x0000000000d3e426 in github.com/opencontainers/runc/libcontainer.(*linuxContainer).Start
        at /root/nestybox/sysbox/sysbox-runc/libcontainer/container_linux.go:287
    11  0x0000000000e1da2e in main.(*runner).run
        at /root/nestybox/sysbox/sysbox-runc/utils_linux.go:383
    12  0x0000000000e1f08f in main.startContainer
        at /root/nestybox/sysbox/sysbox-runc/utils_linux.go:553
    13  0x0000000000e1f78c in main.glob..func2
        at /root/nestybox/sysbox/sysbox-runc/create.go:108
    14  0x0000000000bac838 in github.com/urfave/cli.HandleAction
        at /go/pkg/mod/github.com/urfave/cli@v1.22.1/app.go:523
    15  0x0000000000bade00 in github.com/urfave/cli.Command.Run
        at /go/pkg/mod/github.com/urfave/cli@v1.22.1/command.go:174
    16  0x0000000000baa123 in github.com/urfave/cli.(*App).Run
        at /go/pkg/mod/github.com/urfave/cli@v1.22.1/app.go:276
    17  0x0000000000e11880 in main.main
        at /root/nestybox/sysbox/sysbox-runc/main.go:145
    18  0x000000000043ad24 in runtime.main
        at /usr/local/go/src/runtime/proc.go:203
    19  0x000000000046c0b1 in runtime.goexit
        at /usr/local/go/src/runtime/asm_amd64.s:1357
    (dlv)
    ```

-   Configure the source-code path:

    Sysbox compilation process is carried out inside a docker container. In
    order to do this, we bind-mount the user's Sysbox workspace (i.e.
    "sysbox" folder) into this path within the container: `/root/nestybox/sysbox`.

    Golang compiler includes this path into the generated Sysbox binaries.
    Thereby, if you are debugging Sysbox daemon in your host, unless your
    workspace path fully matches the one above (unlikely), Delve will not be
    able to display the Sysbox source-code.

    The typical solution in these cases is to modify Delve's configuration to
    replace the containerized path with the one of your local environment.

    ```console
    (dlv) config substitute-path /root/nestybox/sysbox /home/rodny/wsp/sysbox
    ```

    The source-code should be now properly shown:

    ```console
    (dlv) frame 10
    > syscall.Syscall6() /usr/local/go/src/syscall/asm_linux_amd64.s:53 (PC: 0x4ead9a)
    Frame 10: /root/nestybox/sysbox/sysbox-runc/libcontainer/container_linux.go:287 (PC: d3e426)
       282:				if err := c.setupShiftfsMarks(); err != nil {
       283:					return err
       284:				}
       285:			}
       286:		}
    => 287:		if err := c.start(process); err != nil {
       288:			if process.Init {
       289:				c.deleteExecFifo()
       290:			}
       291:			return err
       292:		}
    (dlv)
    ```

-   Inspecting POSIX threads:

    ```console
    (dlv) threads
      Thread 2955507 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
      Thread 2955508 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
      Thread 2955509 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
      Thread 2955510 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
      Thread 2955511 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
      Thread 2955512 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
      Thread 2955517 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
    * Thread 2955520 at 0x4ead9a /usr/local/go/src/syscall/asm_linux_amd64.s:53 syscall.Syscall6
      Thread 2955523 at 0x46dfd3 /usr/local/go/src/runtime/sys_linux_amd64.s:536 runtime.futex
      Thread 2955564 at 0x46e180 /usr/local/go/src/runtime/sys_linux_amd64.s:673 runtime.epollwait
    (dlv)
    ```

-   Inspecting goroutines:

    ```console
    (dlv) goroutines
    * Goroutine 1 - User: /usr/local/go/src/syscall/asm_linux_amd64.s:53 syscall.Syscall6 (0x4ead9a) (thread 2955520)
      Goroutine 2 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 3 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 4 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 5 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 9 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 18 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 20 - User: /usr/local/go/src/runtime/sigqueue.go:147 os/signal.signal_recv (0x450dec)
      Goroutine 23 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 26 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      Goroutine 32 - User: /usr/local/go/src/runtime/proc.go:305 runtime.gopark (0x43b0db)
      [11 goroutines]
    (dlv)
    ```

    NOTE: Use `goroutines -t` to show a full stack trace for each goroutine. Then use `frame X` to switch to the desired frame.

- Configure print length of strings:

    ```console
    (dlv) config max-string-len 1000
    ```

- Configure max array size:

   ```console
   (dlv) config max-array-values 600
   ```

- For unit tests, use `dlv test <package> -test.run <test-name>`:

```
dlv test github.com/nestybox/sysbox-runc/libcontainer/integration -test.run TestSysctl
```

  Then set a breakpoint at the desired test line and press `c` (continue).

## Debugging CGO code

To debug cgo code, you must use gdb (delve does not work).

Instructions:

1) Build the cgo code with "go build --buildmode=exe"; do not use "--buildmode=pie", as the position independent code confuses gdb.

-   There may be a gdb option/command to get around this, but it's easier to just build with "--buildmode=exe" during debug.

2) In the golang file that calls cgo, use the "-g" switch, to tell gccgo to generate debug symbols.

```console
    #cgo CFLAGS: -Wall -g
```

3) If needed, instrument the binary to allow you time to attach the
   debugger to it.

-   For example, to attach to the sysbox-runc nsenter child process
    which is normally ephemeral, add an debug "sleep()" to an
    appropriate location within the nsenter (to give you time to find
    the nsenter pid and attach the debugger to it), then execute
    sysbox-runc, find the pid with pstree, and attach gdb to it (next step).

3) Attach gdb to the target process (need root access):

```console
    # gdb --pid 17089

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

```console
    (gdb) file /usr/bin/sysbox-runc
    A program is being debugged already.
    Are you sure you want to change the file? (y or n) y
    Reading symbols from /usr/bin/sysbox-runc...
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

```console
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
`file /var/lib/docker/overlay2/860f62b3bd74c36be6754c8ed8e3f77a63744a2c6b16bef058b22ba0185e2877/merged/usr/bin/sysbox-runc`).
