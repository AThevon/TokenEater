package main

import (
	"encoding/json"
	"fmt"
	"os"
)

type claudeCredentials struct {
	ClaudeAiOauth struct {
		AccessToken string `json:"accessToken"`
	} `json:"claudeAiOauth"`
}

// readToken reads the Claude Code OAuth token from the given credentials file path.
// Default path: ~/.claude/.credentials.json
func readToken(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("reading credentials: %w", err)
	}

	var creds claudeCredentials
	if err := json.Unmarshal(data, &creds); err != nil {
		return "", fmt.Errorf("parsing credentials: %w", err)
	}

	token := creds.ClaudeAiOauth.AccessToken
	if token == "" {
		return "", fmt.Errorf("claudeAiOauth.accessToken is empty or missing in %s", path)
	}
	return token, nil
}

// defaultCredentialsPath returns ~/.claude/.credentials.json
func defaultCredentialsPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolving home directory: %w", err)
	}
	return home + "/.claude/.credentials.json", nil
}
