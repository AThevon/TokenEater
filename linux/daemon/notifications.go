package main

import (
	"fmt"
	"os/exec"
)

// UsageLevel represents usage severity.
type UsageLevel int

const (
	LevelGreen  UsageLevel = 0
	LevelOrange UsageLevel = 1
	LevelRed    UsageLevel = 2
)

func usageLevelFrom(pct int) UsageLevel {
	switch {
	case pct >= 85:
		return LevelRed
	case pct >= 60:
		return LevelOrange
	default:
		return LevelGreen
	}
}

// NotificationState tracks the last notified level per metric key.
type NotificationState struct {
	levels map[string]UsageLevel
}

// checkTransition returns true if a notification should be sent and updates stored level.
func (s *NotificationState) checkTransition(metric string, current UsageLevel) bool {
	if s.levels == nil {
		s.levels = make(map[string]UsageLevel)
	}
	previous, ok := s.levels[metric]
	if !ok {
		previous = LevelGreen
	}
	if current == previous {
		return false
	}
	s.levels[metric] = current
	if current > previous {
		return true // escalation
	}
	if current == LevelGreen && previous > LevelGreen {
		return true // recovery
	}
	return false
}

// notifier wraps notification sending. exec is injectable for testing.
type notifier struct {
	state NotificationState
	exec  func(summary, body, urgency string) error
}

func newNotifier() *notifier {
	n := &notifier{}
	n.exec = notifySend
	return n
}

func notifySend(summary, body, urgency string) error {
	return exec.Command("notify-send",
		"--urgency="+urgency,
		"--app-name=TokenEater",
		summary,
		body,
	).Run()
}

// CheckThresholds checks session, weekly, and Sonnet metrics and sends notifications on transitions.
func (n *notifier) CheckThresholds(usage *UsageResponse) {
	type metric struct {
		key    string
		label  string
		bucket *UsageBucket
	}
	metrics := []metric{
		{"fiveHour", "Session (5h)", usage.FiveHour},
		{"sevenDay", "Weekly — All", usage.SevenDay},
		{"sonnet", "Weekly — Sonnet", usage.SevenDaySonnet},
	}

	for _, m := range metrics {
		if m.bucket == nil {
			continue
		}
		pct := int(m.bucket.Utilization)
		level := usageLevelFrom(pct)
		if !n.state.checkTransition(m.key, level) {
			continue
		}

		switch level {
		case LevelOrange:
			n.exec( //nolint:errcheck
				fmt.Sprintf("⚠️  %s — %d%%", m.label, pct),
				"Usage is climbing. Consider slowing down.",
				"normal",
			)
		case LevelRed:
			n.exec( //nolint:errcheck
				fmt.Sprintf("🔴 %s — %d%%", m.label, pct),
				"Critical usage — approaching the limit!",
				"critical",
			)
		case LevelGreen:
			n.exec( //nolint:errcheck
				fmt.Sprintf("🟢 %s — %d%%", m.label, pct),
				"Usage reset — you're back in the green.",
				"low",
			)
		}
	}
}
