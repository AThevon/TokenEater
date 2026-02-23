package main

import (
	"testing"
	"time"
)

func TestPacing_Hot(t *testing.T) {
	// 50% elapsed of the week, but 70% used → delta = +20 → hot
	resetsAt := time.Now().Add(84 * time.Hour) // 3.5 days left → 50% elapsed
	bucket := &UsageBucket{
		Utilization: 70.0,
		ResetsAt:    resetsAt.UTC().Format(time.RFC3339),
	}
	result, err := calculatePacing(bucket)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Zone != ZoneHot {
		t.Fatalf("want ZoneHot got %v (delta=%.1f)", result.Zone, result.Delta)
	}
	if result.Delta <= 10 {
		t.Fatalf("expected delta > 10, got %.1f", result.Delta)
	}
}

func TestPacing_Chill(t *testing.T) {
	// 50% elapsed, but only 20% used → delta = -30 → chill
	resetsAt := time.Now().Add(84 * time.Hour)
	bucket := &UsageBucket{
		Utilization: 20.0,
		ResetsAt:    resetsAt.UTC().Format(time.RFC3339),
	}
	result, err := calculatePacing(bucket)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Zone != ZoneChill {
		t.Fatalf("want ZoneChill got %v (delta=%.1f)", result.Zone, result.Delta)
	}
	if result.Delta >= -10 {
		t.Fatalf("expected delta < -10, got %.1f", result.Delta)
	}
}

func TestPacing_OnTrack(t *testing.T) {
	// 50% elapsed, 52% used → delta ≈ +2 → on track
	resetsAt := time.Now().Add(84 * time.Hour)
	bucket := &UsageBucket{
		Utilization: 52.0,
		ResetsAt:    resetsAt.UTC().Format(time.RFC3339),
	}
	result, err := calculatePacing(bucket)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Zone != ZoneOnTrack {
		t.Fatalf("want ZoneOnTrack got %v (delta=%.1f)", result.Zone, result.Delta)
	}
}

func TestPacing_NilBucket(t *testing.T) {
	_, err := calculatePacing(nil)
	if err == nil {
		t.Fatal("expected error for nil bucket")
	}
}

func TestPacing_InvalidResetsAt(t *testing.T) {
	bucket := &UsageBucket{Utilization: 50.0, ResetsAt: "not-a-date"}
	_, err := calculatePacing(bucket)
	if err == nil {
		t.Fatal("expected error for invalid resets_at")
	}
}
