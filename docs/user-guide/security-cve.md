# Sysbox User Guide: Security Vulnerabilities & CVEs

This document describes security vulnerabilities / CVEs associated that may
impact the security of Sysbox containers.

These may be vulnerabilities in Sysbox itself (which are remediated fixed
quickly) or in the Linux kernel features that Sysbox uses to isolate containers.

## Summary

| CVE          | Date     | Severity | Affects Sysbox | Details |
| ------------ | -------- | -------- | -------------- | ------- |
| 2022-0185    | 01/21/22 | High     | Yes            | [CVE 2022-0185 (User-Namespace Escape)](#cve-2022-0185-user-namespace-escape) |
| 2022-0492    | 02/06/22 | Medium   | No             | [CVE 2022-0492 (Privilege Escalation via Cgroups v1)](#cve-2022-0492-privilege-escalation-via-cgroups-v1) |
| 2022-0847    | 03/03/22 | High     | Yes            | [CVE-2022-0847 (Privilege Escalation via Pipes (aka Dirty Pipe))](#cve-2022-0847-privilege-escalation-via-pipes-aka-dirty-pipe) |

The sections below describe each of these in more detail.

## CVE 2022-0185 (User-Namespace Escape)

**Date:** 01/21/22

**Severity:** High

**Problem:**

[CVE 2022-0185](https://ubuntu.com/security/CVE-2022-0185) is a vulnerability
in the Linux kernel which permits a "User Namespace" escape (i.e., an
unprivileged user inside a user-namespace may gain root access on the host).

**Effect on Sysbox:**

This vulnerability can negate the extra isolation of containers deployed with
Sysbox as they always use the Linux user-namespace.

**Fix:**

The fix has been [committed][cve-2022-0185-commit] to the Linux kernel on
01/18/22 and picked up by several distros shortly after. For Ubuntu, the fix has
been released and requires a [kernel update](https://ubuntu.com/security/notices/USN-5240-1).

We recommend you upgrade your kernel (i.e., check if your kernel distro carries
the fix and if so, apply it).

## CVE 2022-0492 (Privilege Escalation via Cgroups v1)

**Date:** 02/06/22

**Severity:** Medium

**Problem:**

[CVE 2022-0492](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-0492) is
a flaw in the Linux kernel's cgroups mechanism that under some circumstances
allows the use of the cgroups v1 release_agent feature to escalate privileges.
It affects containers in some cases, as described in this [excellent article](https://unit42.paloaltonetworks.com/cve-2022-0492-cgroups/)
by Unit 42 at Palo Alto Networks.

**Effect on Sysbox:**

Sysbox is NOT vulnerable to the security flaw exposed by this CVE. The reason is
that inside a Sysbox container the cgroups v1 release_agent can't be written
to (by virtue of Sysbox setting up the container with the Linux user-namespace).
Even if you create privileged containers inside a Sysbox container, they won't
be vulnerable due to the Sysbox container's usage of the Linux user-namespace.

**Fix:**

[CVE-2022-0492 is fixed][cve-2022-0492-commit] on the latest Linux release.
Even though this CVE does not affect Sysbox containers, it does affect regular
containers under some scenarios. Therefore we recommend that you check when your
Linux distro picks up the fix and apply it.

## CVE-2022-0847 (Privilege Escalation via Pipes (aka Dirty Pipe))

**Date:** 03/03/22

**Severity:** High

**Problem:**

A flaw in the Linux pipes mechanism allows privilege escalation. Even a process
whose user-ID is "nobody" can elevate its privileges.

**Effect on Sysbox:**

This vulnerability affects containers deployed with Sysbox as it voids
the protection provided by the Linux user-namespace (where processes
in the container run as "nobody:nogroup" at host level).

**Fix:**

The vulnerability first appeared in Linux kernel version 5.8, which was released
in 08/2020. The vulnerability was fixed on 02/21/22 via [this commit][cve-2022-0847-commit]
and available in kernel versions 5.16.11, 5.15.25, and 5.10.102.

We recommend you check when your Linux distro picks up the fix and apply it.




[cve-2022-0185-commit]: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=722d94847de29310e8aa03fcbdb41fc92c521756
[cve-2022-0492-commit]: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=24f6008564183aa120d07c03d9289519c2fe02af
[cve-2022-0847-commit]: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=9d2231c5d74e13b2a0546fee6737ee4446017903
[slack]: https://nestybox-support.slack.com/join/shared_invite/enQtOTA0NDQwMTkzMjg2LTAxNGJjYTU2ZmJkYTZjNDMwNmM4Y2YxNzZiZGJlZDM4OTc1NGUzZDFiNTM4NzM1ZTA2NDE3NzQ1ODg1YzhmNDQ#/
