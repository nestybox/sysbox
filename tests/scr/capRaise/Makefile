all: fileDac mountProcDac

fileDac: fileDac.c
	gcc -Wl,--no-as-needed -lcap fileDac.c -o fileDac

mountProcDac: mountProcDac.c
	gcc -Wl,--no-as-needed -lcap mountProcDac.c -o mountProcDac

clean:
	rm -f fileDac mountProcDac
