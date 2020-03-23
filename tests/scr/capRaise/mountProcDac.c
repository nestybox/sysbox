//
// Copyright 2020 - Nestybox, Inc.
//
// Linux-specifc program that allows a regular (non-root) to mount
// procfs on a given dir bypassing DAC (i.e., by obtaining the
// CAP_DAC_READ_SEARCH and CAP_DAC_OVERRIDE capabilities, as well as
// CAP_SYS_ADMIN).
//
// Note: prior to executing this program, you must set the following
// file capabilities for it:
//
// $ sudo setcap "cap_dac_read_search,cap_dac_override,cap_sys_admin=p" mountProcDac
//
// Usage:
//
// mountProcDac /path/where/procfs/will/be/mounted


#include <sys/capability.h>
#include <sys/mount.h>
#include <stdio.h>
#include <stdlib.h>

static int
changeCaps(int capability, int setting)
{
    cap_t caps;
    cap_value_t capList[1];

    caps = cap_get_proc();
    if (caps == NULL) {
        return -1;
    }

    capList[0] = capability;
    if (cap_set_flag(caps, CAP_EFFECTIVE, 1, capList, setting) == -1) {
       cap_free(caps);
       return -1;
    }

    if (cap_set_proc(caps) == -1) {
       cap_free(caps);
       return -1;
    }

    if (cap_free(caps) == -1) {
       return -1;
    }

    return 0;
}

static int
raiseCap(int capability)
{
   return changeCaps(capability, CAP_SET);
}

static int
dropCap(int capability)
{
   return changeCaps(capability, CAP_CLEAR);
}

void usage(char *progname) {
   printf("Usage: %s /path/where/proc/will/be/mounted\n", progname);
}

int
main(int argc, char *argv[])
{
   char *mountpoint;
   int err;

   // parse command line args
   if (argc < 2) {
      usage(argv[0]);
      exit(EXIT_FAILURE);
   }

   mountpoint = argv[1];

   // raise our capabilities
   if (raiseCap(CAP_SYS_ADMIN) == -1) {
      printf("raiseCap(CAP_SYS_ADMIN) failed\n");
      exit(EXIT_FAILURE);
   }

   if (raiseCap(CAP_DAC_READ_SEARCH) == -1) {
      printf("raiseCap(CAP_DAC_READ_SEARCH) failed\n");
      exit(EXIT_FAILURE);
   }

   if (raiseCap(CAP_DAC_OVERRIDE) == -1) {
      printf("raiseCap(CAP_DAC_OVERRIDE) failed\n");
      exit(EXIT_FAILURE);
   }

   // perform the procfs mount
   err = mount("none", mountpoint, "proc", 0, "");
   if (err != 0) {
      printf("mounting proc at %s failed: %d", mountpoint, err);
      exit(EXIT_FAILURE);
   }

   exit(EXIT_SUCCESS);
}
