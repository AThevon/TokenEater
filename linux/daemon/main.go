package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "tokeneater-daemon starting...")
	os.Exit(0)
}
