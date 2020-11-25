#!/bin/bash -e

/usr/local/sbin/sysbox

# Sleep for good if no command is passed to the container; otherwise run explicit
# command in the foreground. In either case let this instruction become container's
# init.
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
    exec sleep infinity
else
    exec "$@"
fi
