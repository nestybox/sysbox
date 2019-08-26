Sysboxd debugging notes
========================

## Debugging image

Before initiating a debugging session, we must ensure that the
binaries that we will be operating on have been built with
compiler-optimizations disabled. The following sysboxd Makefile
targets have been created for this purpose:

```
sysboxd-debug
sysbox-runc-debug
sysbox-fs-debug
sysbox-mgr-debug
```

Example:

```
$ make sysboxd-debug && sudo make install
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
                if err := sysvisor.CheckHostConfig(context); err != nil {
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
rodny@deepblue-vm-1:~$ cd ~/go/src/github.com/nestybox/sysboxd/sysbox-runc
```

* Attaching to a running process:

```
rodny@deepblue-vm-1:~/go/src/github.com/nestybox/sysboxd/sysbox-runc$ sudo env "PATH=$PATH" env "GOROOT=$GOROOT" env "GOPATH=$GOPATH" env "PWD=$PWD" /home/rodny/go/bin/dlv attach 26558
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
