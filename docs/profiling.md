Sysbox profiling notes
======================

## Profiling image

Before initiating any profiling effort, we must ensure that the
binaries that we will be operating on have been built with
compiler-optimizations turned off, and that code symbols have not
been stripped off.

The following sysbox Makefile targets are available for this
purpose:

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

## Profiling tools

We will make use of [`pprof`](https://github.com/google/pprof) tool
to analyze the results of our profiling sessions; install it by
doing ...

```
go get -u github.com/google/pprof
```

## Profiling session initialization

Both sysbox-fs and sysbox-mgr offer hidden-cli parameters to
initialize profiling data collection. We must simply launch these
daemons with the desired profiling option (see below), and stop
them (i.e. sigterm signal) once we conclude our experiments.

   * `cpu-profiling`
   * `memory-profiling`

Example:

```
sysbox-fs --cpu-profiling --log /var/log/sysbox-fs.log 2>&1 &
```

Notice that the profiling data will not be dumped to the file-system
till the profiling routines are properly shutdown'd, which happens
only once the daemon in question is terminated.

Upon successful termination of the daemon being monitored, we should
see one of these files in sysbox's top-level directory:

   * `cpu.pprof`
   * `mem.pprof`

## Profiling data analysis

The collected information can be processed through the utilization of
the `pprof` tool previously downloaded. See some typical use cases
below:

### Display top-most cpu consumers

Refer to [this](https://blog.golang.org/pprof) link for a proper
explanation on how to interpret the data on each of these columns;
it's important to understand the differences between `top` and
`top -cum` instructions):

```
(pprof) top
Showing nodes accounting for 26060ms, 52.49% of 49650ms total
Dropped 658 nodes (cum <= 248.25ms)
Showing top 10 nodes out of 228
      flat  flat%   sum%        cum   cum%
    8530ms 17.18% 17.18%     9080ms 18.29%  syscall.Syscall
    4830ms  9.73% 26.91%     4830ms  9.73%  runtime.futex
    2870ms  5.78% 32.69%     3090ms  6.22%  syscall.Syscall6
    2470ms  4.97% 37.66%     2470ms  4.97%  runtime.usleep
    1900ms  3.83% 41.49%     1900ms  3.83%  fmt.isSpace
    1440ms  2.90% 44.39%     6690ms 13.47%  fmt.(*ss).ReadRune
    1230ms  2.48% 46.87%     2960ms  5.96%  io.ReadAtLeast
    1010ms  2.03% 48.90%     1720ms  3.46%  fmt.(*stringReader).Read
     930ms  1.87% 50.78%     1160ms  2.34%  runtime.step
     850ms  1.71% 52.49%      970ms  1.95%  strings.Fields
```

## Display top-most memory consumers

```
$ go tool pprof mem.pprof
File: sysbox-fs
Build ID: 0d0fde1c9bc694271f19875a7e21d23aae2e6dec
Type: inuse_space
...
(pprof) top
...
```

Make sure you understand the subtleties between 'inuse_space' and
'alloc_space' as their semantics are different:

```
"go tool pprof has the option to show you either allocation counts
or in use memory. If you’re concerned with the amount of memory
being used, you probably want the inuse metrics, but if you’re
worried about time spent in garbage collection, look at allocations"
```

To switch from one 'mode' (e.g. `inuse` -- default) to another (e.g.
`alloc`) simply do:

```
(pprof) sample_index = alloc_space
```

Refer to this [link](https://jvns.ca/blog/2017/09/24/profiling-go-with-pprof/) for more details.

### Generate graphical representations of most-visited code-paths

Note: You may need to install `graphviz` in your dev VM.

```
(pprof) svg

(pprof) pdf

(pprof) gif

etc
```

### Web UI interaction

Detailed and intuitive representation of all collected data through a Web
interface with features such as:

- Flamegraphs generation (always my favorite)
- Interactive code heat-maps with pruning capabilities
- Traditional flat-profiles visualization
etc

You can benefit from all these features by simply doing:

```
$ go tool pprof -http=:8080 cpu.pprof
```

If the above instruction is executed from a terminal running within a
graphical desktop environment, a web-browser should open automatically.


## References

https://github.com/google/pprof
https://jvns.ca/blog/2017/09/24/profiling-go-with-pprof/
https://blog.detectify.com/2019/09/05/how-we-tracked-down-a-memory-leak-in-one-of-our-go-microservices/