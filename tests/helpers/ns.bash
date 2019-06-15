#!/bin/bash

#
# Namespace helpers
#

# unshare all namespaces and execute the given command as a forked process
function unshare_all() {
  if [ "$#" -eq 0 ]; then
     return 1
  fi

  unshare -i -m -n -p -u -U -C -f --mount-proc -r "$@"
}
