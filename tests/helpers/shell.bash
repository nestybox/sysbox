#!/bin/bash

#
# Generic shell/bash routines.
#

# Function converts a multi-line string into an array.
#
# Example:
#
#  ```
#  stringList="
#  1
#  2
#  3"
#
#  stringToArray "${stringList}" resultArray
#  declare -p resultArray
#  ```
#
# output: resultArray=([0]="1" [1]="2" [2]="3")
#
function stringToArray() {
  local str="$1"
  local -n arr="$2"

  SAVEIFS=$IFS       # Save current IFS
  IFS=$'\n'          # Change IFS to newline char
  arr=($str)         # split the `str` string into an array
  IFS=$SAVEIFS       # Restore original IFS
}
