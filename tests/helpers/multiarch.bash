#!/bin/bash

. $(dirname ${BASH_SOURCE[0]})/environment.bash

#
# Multi-arch helper functions
#

function binfmt_misc_module_present() {
  modprobe binfmt_misc
}

function kernel_supports_binfmt_misc_namespacing() {
  local cur_kernel=$(get_kernel_release_semver)
  semver_ge ${cur_kernel} "6.7.0"
}
