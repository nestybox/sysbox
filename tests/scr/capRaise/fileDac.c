//
// Copyright 2020 - Nestybox, Inc.
//
// Linux-specifc program that allows a regular (non-root) user to
// access a given file bypassing DAC by obtaining the
// CAP_DAC_READ_SEARCH and CAP_DAC_OVERRIDE capabilities.
//
// Note: prior to executing this program, you must set the following
// file capabilities for it:
//
// $ sudo setcap "cap_dac_read_search,cap_dac_override=p" fileDac
//
// Usage:
//
// fileDac op=[read|write] file data
//
// E.g.
//
// fileDac read somefile
// fileDac write somefile somedata

#include <sys/capability.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

typedef enum opType {Read, Write} opType;

void usage(char *progname) {
   printf("Usage: %s op=[read|write] file data\n", progname);
}

int
main(int argc, char *argv[])
{
   FILE *fp;
   char *filename, *op, *data;
   int ch;
   opType optype;

   // parse command line args
   if (argc < 3) {
      usage(argv[0]);
      exit(EXIT_FAILURE);
   }

   op = argv[1];
   filename = argv[2];

   if ((strcmp(op, "write")) == 0) {
      optype = Write;
   } else {
      optype = Read;
   }

   if (optype == Write) {
      if (argc < 4) {
         usage(argv[0]);
         exit(EXIT_FAILURE);
      }
      data = argv[3];
   }

   // raise our capabilities
   if (raiseCap(CAP_DAC_READ_SEARCH) == -1) {
      printf("raiseCap(CAP_DAC_READ_SEARCH) failed\n");
      exit(EXIT_FAILURE);
   }

   if (raiseCap(CAP_DAC_OVERRIDE) == -1) {
      printf("raiseCap(CAP_DAC_OVERRIDE) failed\n");
      exit(EXIT_FAILURE);
   }

   // perform the access
   if (optype == Write) {
      fp = fopen(filename, "w" );
      if (!fp) {
         printf("Failed to open %s\n", filename);
         exit(EXIT_FAILURE);
      }
      fprintf(fp, "%s", data);
   } else {
      fp = fopen(filename, "r" );
      if (!fp) {
         printf("Failed to open %s\n", filename);
         exit(EXIT_FAILURE);
      }
      while ((ch = fgetc(fp)) != EOF ) {
         printf("%c",ch);
      }
      printf("\n");
   }

   fclose(fp);
   exit(EXIT_SUCCESS);
}
