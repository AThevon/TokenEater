package main

import (
	"fmt"
	"time"
)

// PacingZone represents the usage pace relative to expected consumption.
type PacingZone string

const (
	ZoneChill   PacingZone = "chill"
	ZoneOnTrack PacingZone = "onTrack"
	ZoneHot     PacingZone = "hot"
)

// PacingResult holds the pacing calculation output.
type PacingResult struct {
	Delta         float64
	ExpectedUsage float64
	ActualUsage   float64
	Zone          PacingZone
}

const weekDuration = 7 * 24 * time.Hour

// calculatePacing ports PacingCalculator.swift.
// Compares actual utilization against expected linear consumption for the 7-day window.
func calculatePacing(bucket *UsageBucket) (*PacingResult, error) {
	if bucket == nil {
		return nil, fmt.Errorf("seven_day bucket is nil")
	}
	resetsAt, err := bucket.ResetsAtTime()
	if err != nil {
		return nil, fmt.Errorf("parsing resets_at: %w", err)
	}

	now := time.Now()
	startOfPeriod := resetsAt.Add(-weekDuration)
	elapsed := now.Sub(startOfPeriod).Seconds() / weekDuration.Seconds()
	if elapsed < 0 {
		elapsed = 0
	} else if elapsed > 1 {
		elapsed = 1
	}

	expectedUsage := elapsed * 100
	delta := bucket.Utilization - expectedUsage

	var zone PacingZone
	switch {
	case delta < -10:
		zone = ZoneChill
	case delta > 10:
		zone = ZoneHot
	default:
		zone = ZoneOnTrack
	}

	return &PacingResult{
		Delta:         delta,
		ExpectedUsage: expectedUsage,
		ActualUsage:   bucket.Utilization,
		Zone:          zone,
	}, nil
}
