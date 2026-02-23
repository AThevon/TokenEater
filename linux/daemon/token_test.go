package main

import (
	"encoding/json"
	"os"
	"path/filepath"
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
	data, _ := json.Marshal(payload)
	os.WriteFile(credPath, data, 0600)

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
	os.WriteFile(credPath, []byte(`{}`), 0600)

	_, err := readToken(credPath)
	if err == nil {
		t.Fatal("expected error when claudeAiOauth key missing")
	}
}
