all: fileDac mountProcDac

fileDac: fileDac.c
	gcc -Wl,--no-as-needed -lcap fileDac.c -o fileDac
chown rootless:rootless fileDac

mountProcDac: mountProcDac.c
	gcc -Wl,--no-as-needed -lcap mountProcDac.c -o mountProcDac
	chown rootless:rootless mountProcDac

clean:
	rm -f fileDac mountProcDac
