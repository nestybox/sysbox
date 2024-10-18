#!/bin/bash

#
# uuid related helpers
#
# Note: these should not use bats, so as to allow their use
# when manually reproducing tests.
#

# verifies the given uuid is valid (e.g., similar to "abaee0f3-5cd9-4824-a5ac-9d49e83e2721")
function is_valid_uuid() {
  local uuid="$1"
  if [[ $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    return 0
  else
    return 1
  fi
}
