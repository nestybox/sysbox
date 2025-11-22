package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/sys/unix"
)

// Map of flag names to their values
var flagMap = map[string]uint64{
	"O_PATH":      uint64(unix.O_PATH),
	"O_RDONLY":    uint64(unix.O_RDONLY),
	"O_WRONLY":    uint64(unix.O_WRONLY),
	"O_RDWR":      uint64(unix.O_RDWR),
	"O_APPEND":    uint64(unix.O_APPEND),
	"O_CLOEXEC":   uint64(unix.O_CLOEXEC),
	"O_CREAT":     uint64(unix.O_CREAT),
	"O_DIRECTORY": uint64(unix.O_DIRECTORY),
	"O_EXCL":      uint64(unix.O_EXCL),
	"O_NOCTTY":    uint64(unix.O_NOCTTY),
	"O_NOFOLLOW":  uint64(unix.O_NOFOLLOW),
	"O_TRUNC":     uint64(unix.O_TRUNC),
}

// Map of resolve flag names to their values
var resolveMap = map[string]uint64{
	"RESOLVE_NO_XDEV":       0x01,
	"RESOLVE_NO_MAGICLINKS": 0x02,
	"RESOLVE_NO_SYMLINKS":   0x04,
	"RESOLVE_BENEATH":       0x08,
	"RESOLVE_IN_ROOT":       0x10,
	"RESOLVE_CACHED":        0x20,
}

func parseFlags(flagStr string) (uint64, error) {
	if flagStr == "" {
		return uint64(unix.O_RDONLY), nil
	}

	var result uint64
	parts := strings.Split(flagStr, "|")
	for _, part := range parts {
		part = strings.TrimSpace(part)
		val, ok := flagMap[part]
		if !ok {
			return 0, fmt.Errorf("unknown flag: %s", part)
		}
		result |= val
	}
	return result, nil
}

func parseResolve(resolveStr string) (uint64, error) {
	if resolveStr == "" {
		return 0, nil
	}

	var result uint64
	parts := strings.Split(resolveStr, "|")
	for _, part := range parts {
		part = strings.TrimSpace(part)
		val, ok := resolveMap[part]
		if !ok {
			return 0, fmt.Errorf("unknown resolve flag: %s", part)
		}
		result |= val
	}
	return result, nil
}

func main() {
	flagsStr := flag.String("flags", "O_RDONLY", "Open flags (e.g., 'O_RDONLY', 'O_RDWR|O_CREAT')")
	resolveStr := flag.String("resolve", "", "Resolve flags (e.g., 'RESOLVE_NO_SYMLINKS', 'RESOLVE_IN_ROOT|RESOLVE_NO_XDEV')")
	expectedVal := flag.String("expected", "", "Expected file contents for comparison (optional)")
	verbose := flag.Bool("v", false, "Verbose output (show file info and contents)")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s [options] <path>\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "\nOptions:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nAvailable flags:\n")
		for name := range flagMap {
			fmt.Fprintf(os.Stderr, "  %s\n", name)
		}
		fmt.Fprintf(os.Stderr, "\nAvailable resolve flags:\n")
		for name := range resolveMap {
			fmt.Fprintf(os.Stderr, "  %s\n", name)
		}
		fmt.Fprintf(os.Stderr, "\nExample:\n")
		fmt.Fprintf(os.Stderr, "  %s -flags 'O_RDONLY|O_CLOEXEC' -resolve 'RESOLVE_IN_ROOT' -expected '1024' /proc/sys/net/ipv4/ip_unprivileged_port_start\n", os.Args[0])
	}

	flag.Parse()

	if flag.NArg() < 1 {
		flag.Usage()
		os.Exit(1)
	}

	path := flag.Arg(0)

	// Parse flags and resolve options
	flags, err := parseFlags(*flagsStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing flags: %v\n", err)
		os.Exit(1)
	}

	resolve, err := parseResolve(*resolveStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing resolve: %v\n", err)
		os.Exit(1)
	}

	// Prepare the OpenHow structure for openat2
	how := &unix.OpenHow{
		Flags:   flags,
		Mode:    0,
		Resolve: resolve,
	}

	if *verbose {
		fmt.Printf("Opening %s with flags=%#x, resolve=%#x\n", path, flags, resolve)
	}

	fd, err := unix.Openat2(unix.AT_FDCWD, path, how)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error opening %s with openat2: %v\n", path, err)
		os.Exit(1)
	}
	defer unix.Close(fd)

	if *verbose {
		fmt.Printf("Successfully opened %s with openat2, fd=%d\n", path, fd)
	}

	// Create a file object from the file descriptor
	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		fmt.Fprintf(os.Stderr, "Error creating os.File from fd %d\n", fd)
		os.Exit(1)
	}
	defer file.Close()

	// Stat the file to get its info
	fileInfo, err := file.Stat()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error stating file: %v\n", err)
		os.Exit(1)
	}

	if *verbose {
		fmt.Printf("File info:\n")
		fmt.Printf("  Name: %s\n", fileInfo.Name())
		fmt.Printf("  Size: %d bytes\n", fileInfo.Size())
		fmt.Printf("  Mode: %s\n", fileInfo.Mode())
		fmt.Printf("  ModTime: %s\n", fileInfo.ModTime())
		fmt.Printf("  IsDir: %t\n", fileInfo.IsDir())
	}

	// Read the file contents
	contents, err := io.ReadAll(file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading from fd %d: %v\n", fd, err)
		os.Exit(1)
	}

	contentsStr := strings.TrimSpace(string(contents))
	if *verbose {
		fmt.Printf("Contents of %s: %s\n", path, contentsStr)
	}

	// Compare with expected value if provided
	if *expectedVal != "" {
		expectedTrimmed := strings.TrimSpace(*expectedVal)
		if contentsStr == expectedTrimmed {
			fmt.Printf("✓ Content matches expected value: %s\n", expectedTrimmed)
		} else {
			fmt.Fprintf(os.Stderr, "✗ Content mismatch!\n")
			fmt.Fprintf(os.Stderr, "  Expected: %s\n", expectedTrimmed)
			fmt.Fprintf(os.Stderr, "  Got:      %s\n", contentsStr)
			os.Exit(1)
		}
	}

	fmt.Println("Test completed successfully!")
}
