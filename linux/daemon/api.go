package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// UsageResponse mirrors the Anthropic API response.
type UsageResponse struct {
	FiveHour          *UsageBucket `json:"five_hour"`
	SevenDay          *UsageBucket `json:"seven_day"`
	SevenDaySonnet    *UsageBucket `json:"seven_day_sonnet"`
	SevenDayOauthApps *UsageBucket `json:"seven_day_oauth_apps"`
	SevenDayOpus      *UsageBucket `json:"seven_day_opus"`
}

// UsageBucket holds a single limit bucket.
type UsageBucket struct {
	Utilization float64 `json:"utilization"`
	ResetsAt    string  `json:"resets_at"`
}

// ResetsAtTime parses ResetsAt as time.Time.
func (b *UsageBucket) ResetsAtTime() (time.Time, error) {
	if b.ResetsAt == "" {
		return time.Time{}, fmt.Errorf("resets_at is empty")
	}
	return time.Parse(time.RFC3339, b.ResetsAt)
}

const defaultBaseURL = "https://api.anthropic.com/api/oauth/"

// APIClient calls the Anthropic usage API.
type APIClient struct {
	baseURL    string
	httpClient *http.Client
}

func newAPIClient() *APIClient {
	return &APIClient{
		baseURL:    defaultBaseURL,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}
}

func (c *APIClient) fetchUsage(token string) (*UsageResponse, error) {
	url := c.baseURL + "usage"
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("building request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("anthropic-beta", "oauth-2025-04-20")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusUnauthorized, http.StatusForbidden:
		return nil, fmt.Errorf("token expired or unauthorized (HTTP %d)", resp.StatusCode)
	default:
		return nil, fmt.Errorf("unexpected HTTP status %d", resp.StatusCode)
	}

	var usage UsageResponse
	if err := json.NewDecoder(resp.Body).Decode(&usage); err != nil {
		return nil, fmt.Errorf("decoding response: %w", err)
	}
	return &usage, nil
}
