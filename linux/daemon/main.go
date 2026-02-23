package main

import (
	"fmt"
	"os"
)

func main() {
	credPath, err := defaultCredentialsPath()
	if err != nil {
		fmt.Fprintf(os.Stderr, "tokeneater-daemon: %v\n", err)
		os.Exit(1)
	}
	_ = credPath
	fmt.Fprintln(os.Stderr, "tokeneater-daemon starting...")
	os.Exit(0)
}
