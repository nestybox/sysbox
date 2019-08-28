#!/bin/bash
#
# Copyright: (C) 2019 Nestybox Inc.  All rights reserved.
#
# Description: Script converts a user-defined changelog file into a
# debian-friendly counterpart.
#
# Required input:
#
# User-defined changelog file must necesarily utilize the following layout:
#
# $ cat CHANGELOG.md
# ...
# ## [0.0.2] - unreleased
# ### Added
#  * Generate external documentation: README, user-guide, design-guide, etc.
#  * Extend Sysboxd support to Ubuntu-Bionic.
#
# ## [0.0.1] - 2019-06-23
# ### Added
#  * Initial public release.
# ...
#
# Expected output:
#
# $ cat image/deb/common/changelog
# ...
# sysboxd (0.0.2) unstable; urgency=low
#
#  * Generate external documentation: README, user-guide, design-guide, etc.
#  * Extend Sysboxd support to Ubuntu-Bionic.
#
#  -- Rodny Molina <rmolina@nestybox.com> Tue, 20 Aug 2019 16:21:10 -0700
#
# sysboxd (0.0.1) unstable; urgency=low
#
#  * Initial public release.
#
#  -- Rodny Molina <rmolina@nestybox.com> Tue, 23 Jul 2019 17:37:44 -0400
# ...

# Note that CHANGELOG.md file will be parsed attending to the two following
# reg-expresions. Anything that doesn't match this pattern will be ignored.
#
# - "^## "  Example: "## [0.0.1] - 2019-06-23
# - "^ * "  Example: " * Extend Sysboxd support to Ubuntu-Bionic."
#


# Input file to be created/edited by whoever creates a new Sysboxd release.
user_changelog="sysboxd/CHANGELOG.md"

# Output file to be generated by this script, and to be included in Sysboxd's
# debian-package installer.
debian_changelog="debian/changelog"

# Redirect all generated output.
exec > ${debian_changelog}


print_tag_header() {

    local tag=$1
    local unreleased=$2

    if [[ $unreleased = true ]]; then
        echo -e "sysboxd ($tag-0~${DISTRO}-${SUITE}) ${SUITE} UNRELEASED; urgency=medium\n"
    else
        echo -e "sysboxd ($tag-0~${DISTRO}-${SUITE}) ${SUITE} unstable; urgency=medium\n"
    fi
}

print_tag_trailer() {

    local tag=$1
    local unreleased=$2

    local tag_author=""
    local tag_email=""
    local tag_date=""


    if [[ "$unreleased" = true ]]; then
        tag_author="Nestybox builder-bot"
        tag_email="builder-bot@nestybox.com"
        tag_date=$(date --rfc-2822)
    else
        # Temporarily commenting these lines out to avoid exposing personal emails.
        #local tag_author=$(git -C sysboxd log -1 --format=%aN v$1)
        #local tag_email=$(git -C sysboxd log -1 --format=%ae v$1)
        tag_author="Nestybox builder-bot"
        tag_email="builder-bot@nestybox.com"
        tag_date=$(git -C sysboxd log -1 --format=%aD v$tag)
    fi
    
    echo -e "\n -- ${tag_author} <${tag_email}>  ${tag_date}\n"    
}

main () {
    local currTag=""
    local prevTag=""
    local unreleased=""
    local prevUnreleased=""

    # Make sure a user-defined changelog is alredy available.
    if [[ ! -f ${user_changelog} ]]; then
        echo "Sysboxd CHANGELOG.md file not found. Exiting..."
        exit 1
    fi

    # Iterate though CHANGELOG.md file to extract relevant information.
    while IFS= read -r line; do
        if echo ${line} | egrep -q "^## "; then

            currTag=$(echo ${line} | cut -d"[" -f2 | cut -d"]" -f1)
            
            if echo ${line} | egrep -q "unreleased"; then
                unreleased=true
            else
                unreleased=false
            fi

            if [[ ${currTag} != ${prevTag} ]] && [[ ${prevTag} != "" ]]; then
                print_tag_trailer ${prevTag} ${prevUnreleased}
            fi

            print_tag_header ${currTag} ${unreleased}

            prevTag=${currTag}
	    prevUnreleased=${unreleased}
    
        elif echo "${line}" | egrep -q "^ * "; then
            echo -e "${line}"
        fi

    done < ${user_changelog}

    print_tag_trailer ${currTag} ${unreleased}
}

main
