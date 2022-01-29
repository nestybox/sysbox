all: fileDac mountProcDac

fileDac: fileDac.c
	gcc -Wl,--no-as-needed -lcap fileDac.c -o fileDac
	chown root:root fileDac

mountProcDac: mountProcDac.c
	gcc -Wl,--no-as-needed -lcap mountProcDac.c -o mountProcDac
	chown root:root mountProcDac

clean:
	rm -f fileDac mountProcDac
