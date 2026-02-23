package main

import (
	"encoding/json"
	"time"
)

// DaemonState is the JSON payload emitted on D-Bus and cached on disk.
type DaemonState struct {
	FiveHour       *BucketState `json:"fiveHour,omitempty"`
	SevenDay       *BucketState `json:"sevenDay,omitempty"`
	SevenDaySonnet *BucketState `json:"sevenDaySonnet,omitempty"`
	Pacing         *PacingState `json:"pacing,omitempty"`
	FetchedAt      time.Time    `json:"fetchedAt"`
	Error          string       `json:"error,omitempty"`
}

// BucketState is the serializable form of a UsageBucket.
type BucketState struct {
	Utilization float64 `json:"utilization"`
	ResetsAt    string  `json:"resetsAt"`
}

// PacingState is the serializable form of a PacingResult.
type PacingState struct {
	Delta         float64    `json:"delta"`
	Zone          PacingZone `json:"zone"`
	ExpectedUsage float64    `json:"expectedUsage"`
}

// buildState constructs a DaemonState from a fetch result.
// If fetchErr is non-nil, only Error and FetchedAt are populated.
func buildState(usage *UsageResponse, pacing *PacingResult, fetchErr error) DaemonState {
	s := DaemonState{FetchedAt: time.Now()}

	if fetchErr != nil {
		s.Error = fetchErr.Error()
		return s
	}

	if usage.FiveHour != nil {
		s.FiveHour = &BucketState{
			Utilization: usage.FiveHour.Utilization,
			ResetsAt:    usage.FiveHour.ResetsAt,
		}
	}
	if usage.SevenDay != nil {
		s.SevenDay = &BucketState{
			Utilization: usage.SevenDay.Utilization,
			ResetsAt:    usage.SevenDay.ResetsAt,
		}
	}
	if usage.SevenDaySonnet != nil {
		s.SevenDaySonnet = &BucketState{
			Utilization: usage.SevenDaySonnet.Utilization,
			ResetsAt:    usage.SevenDaySonnet.ResetsAt,
		}
	}
	if pacing != nil {
		s.Pacing = &PacingState{
			Delta:         pacing.Delta,
			Zone:          pacing.Zone,
			ExpectedUsage: pacing.ExpectedUsage,
		}
	}
	return s
}

// JSON serializes the state to a JSON string.
func (s DaemonState) JSON() string {
	data, _ := json.Marshal(s)
	return string(data)
}
