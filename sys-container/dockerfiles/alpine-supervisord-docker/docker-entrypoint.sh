#!/bin/sh
set -e

# sys container init:
#
# If no command is passed to the container, supervisord becomes init and
# starts all its configured programs (per /etc/supervisor/conf.f/supervisord.conf).
#
# If a command is passed to the container, it runs in the foreground;
# supervisord runs in the background and starts all its configured
# programs.
#
# In either case, supervisord always starts its configured programs.

if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
  exec supervisord -n "$@"
else
  supervisord -c /etc/supervisor/conf.d/supervisord.conf &
  exec "$@"
fi
