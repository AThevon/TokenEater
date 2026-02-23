package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadToken_Success(t *testing.T) {
	tmp := t.TempDir()
	credPath := filepath.Join(tmp, ".credentials.json")

	payload := map[string]any{
		"claudeAiOauth": map[string]any{
			"accessToken": "test-token-abc",
		},
	}
	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("failed to marshal test payload: %v", err)
	}
	if err := os.WriteFile(credPath, data, 0600); err != nil {
		t.Fatalf("failed to write credentials fixture: %v", err)
	}

	got, err := readToken(credPath)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "test-token-abc" {
		t.Fatalf("want %q got %q", "test-token-abc", got)
	}
}

func TestReadToken_FileNotFound(t *testing.T) {
	_, err := readToken("/nonexistent/path/.credentials.json")
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestReadToken_MissingKey(t *testing.T) {
	tmp := t.TempDir()
	credPath := filepath.Join(tmp, ".credentials.json")
	if err := os.WriteFile(credPath, []byte(`{}`), 0600); err != nil {
		t.Fatalf("failed to write credentials fixture: %v", err)
	}

	_, err := readToken(credPath)
	if err == nil {
		t.Fatal("expected error when claudeAiOauth key missing")
	}
}

func TestReadToken_InvalidJSON(t *testing.T) {
	tmp := t.TempDir()
	credPath := filepath.Join(tmp, ".credentials.json")
	if err := os.WriteFile(credPath, []byte(`{not valid json`), 0600); err != nil {
		t.Fatalf("setup: %v", err)
	}
	_, err := readToken(credPath)
	if err == nil {
		t.Fatal("expected error for malformed JSON")
	}
}

func TestDefaultCredentialsPath(t *testing.T) {
	path, err := defaultCredentialsPath()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasSuffix(path, "/.claude/.credentials.json") {
		t.Fatalf("expected path to end with /.claude/.credentials.json, got %q", path)
	}
}
