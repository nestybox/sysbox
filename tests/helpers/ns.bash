#!/bin/bash

#
# Namespace helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

# Linux kernel namespaced resources under /proc/sys
# (representative list, not exhaustive)
PROC_SYS_NS=('e=(/proc/sys/net/ipv4/ip_default_ttl INT)' \
             'e=(/proc/sys/net/ipv4/ip_forward BOOL)' \
             'e=(/proc/sys/net/ipv4/tcp_keepalive_time INT)' \
             'e=(/proc/sys/net/ipv6/idgen_retries INT)' \
             'e=(/proc/sys/net/ipv6/ip_nonlocal_bind BOOL)' \
             'e=(/proc/sys/net/ipv6/conf/all/disable_ipv6 BOOL)' \
             'e=(/proc/sys/net/ipv6/conf/all/forwarding BOOL)' \
             'e=(/proc/sys/net/ipv6/conf/default/keep_addr_on_down BOOL)' \
             'e=(/proc/sys/net/netfilter/nf_conntrack_icmp_timeout INT)' \
             'e=(/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait INT)' \
             'e=(/proc/sys/net/netfilter/nf_conntrack_udp_timeout INT)' \
             'e=(/proc/sys/user/max_net_namespaces INT)' \
             'e=(/proc/sys/user/max_pid_namespaces INT)' \
             'e=(/proc/sys/user/max_inotify_watches INT)')

# Linux kernel non-namespaced resources under /proc/sys
# (representative list, not exhaustive)
PROC_SYS_NON_NS=('e=(/proc/sys/abi/vsyscall32 BOOL) '\
                 'e=(/proc/sys/debug/exception-trace BOOL) '\
                 'e=(/proc/sys/debug/kprobes-optimization BOOL) '\
                 'e=(/proc/sys/fs/file-max INT) '\
                 'e=(/proc/sys/fs/pipe-max-size INT) '\
                 'e=(/proc/sys/fs/mount-max INT)' \
                 'e=(/proc/sys/fs/mqueue/msg_max INT)'
                 'e=(/proc/sys/kernel/cap_last_cap INT)' \
                 'e=(/proc/sys/kernel/shmmni INT)' \
                 'e=(/proc/sys/kernel/sysrq INT)' \
                 'e=(/proc/sys/kernel/threads-max INT) '\
                 'e=(/proc/sys/kernel/unprivileged_userns_clone BOOL)' \
                 'e=(/proc/sys/kernel/keys/maxkeys INT)' \
                 'e=(/proc/sys/vm/swappiness INT)' \
                 'e=(/proc/sys/vm/zone_reclaim_mode BOOL)')

# unshare all namespaces and execute the given command as a forked process
function unshare_all() {
  if [ "$#" -eq 0 ]; then
     return 1
  fi

  unshare -i -m -n -p -u -U -C -f --mount-proc -r "$@"
}
