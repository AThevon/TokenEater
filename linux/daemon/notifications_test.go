package main

import (
	"testing"
)

func TestUsageLevel_From(t *testing.T) {
	cases := []struct {
		pct  int
		want UsageLevel
	}{
		{0, LevelGreen},
		{59, LevelGreen},
		{60, LevelOrange},
		{84, LevelOrange},
		{85, LevelRed},
		{100, LevelRed},
	}
	for _, c := range cases {
		got := usageLevelFrom(c.pct)
		if got != c.want {
			t.Errorf("pct=%d: want %v got %v", c.pct, c.want, got)
		}
	}
}

func TestNotificationState_NoTransition(t *testing.T) {
	state := &NotificationState{}
	// green → green: no notification
	if state.checkTransition("session", LevelGreen) {
		t.Error("should not notify: no level change from default green")
	}
}

func TestNotificationState_Escalation(t *testing.T) {
	state := &NotificationState{}
	// green → orange: notify
	if !state.checkTransition("session", LevelOrange) {
		t.Error("should notify on green→orange escalation")
	}
	// orange → orange: no notify
	if state.checkTransition("session", LevelOrange) {
		t.Error("should not notify: same level")
	}
	// orange → red: notify
	if !state.checkTransition("session", LevelRed) {
		t.Error("should notify on orange→red escalation")
	}
}

func TestNotificationState_Recovery(t *testing.T) {
	state := &NotificationState{}
	state.checkTransition("session", LevelOrange)
	state.checkTransition("session", LevelRed)
	// red → green: notify (recovery)
	if !state.checkTransition("session", LevelGreen) {
		t.Error("should notify on recovery to green")
	}
}

func TestNotificationState_NoRecoveryToOrange(t *testing.T) {
	state := &NotificationState{}
	state.checkTransition("session", LevelRed)
	// red → orange: NOT a recovery (not back to green), should NOT notify
	if state.checkTransition("session", LevelOrange) {
		t.Error("should not notify on red→orange (not a recovery)")
	}
}

func TestNotifier_CheckThresholds_NilBuckets(t *testing.T) {
	notified := false
	n := &notifier{
		exec: func(summary, body, urgency string) error {
			notified = true
			return nil
		},
	}
	n.CheckThresholds(&UsageResponse{}) // all nil buckets
	if notified {
		t.Error("should not notify when all buckets are nil")
	}
}

func TestNotifier_CheckThresholds_Escalation(t *testing.T) {
	var calls []string
	n := &notifier{
		exec: func(summary, body, urgency string) error {
			calls = append(calls, urgency)
			return nil
		},
	}
	usage := &UsageResponse{
		FiveHour: &UsageBucket{Utilization: 70.0}, // orange
	}
	n.CheckThresholds(usage)
	if len(calls) != 1 {
		t.Fatalf("expected 1 notification, got %d", len(calls))
	}
	if calls[0] != "normal" {
		t.Errorf("expected urgency 'normal' for orange, got %q", calls[0])
	}
}
