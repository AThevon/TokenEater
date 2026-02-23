package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetchUsage_Success(t *testing.T) {
	payload := map[string]any{
		"five_hour": map[string]any{"utilization": 67.0, "resets_at": "2026-02-23T18:00:00Z"},
		"seven_day": map[string]any{"utilization": 28.0, "resets_at": "2026-02-25T12:00:00Z"},
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		if r.Header.Get("anthropic-beta") != "oauth-2025-04-20" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		json.NewEncoder(w).Encode(payload)
	}))
	defer srv.Close()

	client := &APIClient{baseURL: srv.URL + "/", httpClient: srv.Client()}
	resp, err := client.fetchUsage("test-token")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.FiveHour == nil {
		t.Fatal("FiveHour bucket is nil")
	}
	if resp.FiveHour.Utilization != 67.0 {
		t.Fatalf("want 67.0 got %v", resp.FiveHour.Utilization)
	}
	if resp.SevenDay == nil {
		t.Fatal("SevenDay bucket is nil")
	}
}

func TestFetchUsage_Unauthorized(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	client := &APIClient{baseURL: srv.URL + "/", httpClient: srv.Client()}
	_, err := client.fetchUsage("bad-token")
	if err == nil {
		t.Fatal("expected error for 401")
	}
}

func TestFetchUsage_ServerError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	client := &APIClient{baseURL: srv.URL + "/", httpClient: srv.Client()}
	_, err := client.fetchUsage("test-token")
	if err == nil {
		t.Fatal("expected error for 500")
	}
}

func TestUsageBucket_ResetsAtTime(t *testing.T) {
	b := &UsageBucket{ResetsAt: "2026-02-23T18:00:00Z"}
	ts, err := b.ResetsAtTime()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ts.Year() != 2026 || ts.Month() != 2 || ts.Day() != 23 {
		t.Fatalf("wrong date: %v", ts)
	}
}
