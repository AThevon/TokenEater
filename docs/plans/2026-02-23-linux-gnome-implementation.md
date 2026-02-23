# TokenEater Linux/GNOME — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port TokenEater to Linux as a Go daemon exposing usage data via D-Bus + a GNOME Shell extension that shows usage in the top bar with a detailed popup.

**Architecture:** A Go daemon (`tokeneater-daemon`) runs as a systemd user service, reads the Claude Code OAuth token from `~/.claude/.credentials.json`, polls the Anthropic usage API every 5 minutes, computes pacing, fires `notify-send` desktop notifications on threshold transitions, and exposes a D-Bus interface (`io.tokeneater.Daemon`) on the session bus. The GNOME Shell extension (GJS) subscribes to D-Bus signals to update the status bar label reactively and renders a popup with progress bars on click.

**Tech Stack:** Go 1.22+, `github.com/godbus/dbus/v5`, GJS (GNOME Shell extensions), systemd user services, `notify-send`

**Design doc:** `docs/plans/2026-02-23-linux-gnome-design.md`

---

## Prerequisites

Before starting, verify on the dev machine:

```bash
go version           # 1.22+
notify-send --version
gnome-shell --version
systemctl --user status  # should work (not root)
cat ~/.claude/.credentials.json | python3 -m json.tool  # should show claudeAiOauth.accessToken
```

---

## Task 1: Go module + project structure

**Files:**
- Create: `linux/daemon/go.mod`
- Create: `linux/daemon/go.sum` (generated)
- Create: `linux/daemon/main.go`

**Step 1: Create the directory and initialize the Go module**

```bash
mkdir -p linux/daemon
cd linux/daemon
go mod init tokeneater
```

**Step 2: Add the D-Bus dependency**

```bash
go get github.com/godbus/dbus/v5@latest
```

**Step 3: Create `linux/daemon/main.go` with a minimal stub**

```go
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "tokeneater-daemon starting...")
	os.Exit(0)
}
```

**Step 4: Verify it compiles**

```bash
cd linux/daemon && go build ./...
```
Expected: no output, binary `daemon` created (or `tokeneater` if named by module).

**Step 5: Commit**

```bash
git add linux/daemon/go.mod linux/daemon/go.sum linux/daemon/main.go
git commit -m "feat(linux): init Go daemon module"
```

---

## Task 2: Token reader

**Files:**
- Create: `linux/daemon/token.go`
- Create: `linux/daemon/token_test.go`

**Step 1: Write the failing test**

Create `linux/daemon/token_test.go`:

```go
package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestReadToken_Success(t *testing.T) {
	// Write a fake credentials file
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
```

**Step 2: Run test to verify it fails**

```bash
cd linux/daemon && go test ./... -run TestReadToken -v
```
Expected: compile error (`readToken` undefined).

**Step 3: Implement `linux/daemon/token.go`**

```go
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
func defaultCredentialsPath() string {
	home, _ := os.UserHomeDir()
	return home + "/.claude/.credentials.json"
}
```

**Step 4: Run tests to verify they pass**

```bash
cd linux/daemon && go test ./... -run TestReadToken -v
```
Expected: all 3 tests PASS.

**Step 5: Commit**

```bash
git add linux/daemon/token.go linux/daemon/token_test.go
git commit -m "feat(linux/daemon): token reader for ~/.claude/.credentials.json"
```

---

## Task 3: API client

**Files:**
- Create: `linux/daemon/api.go`
- Create: `linux/daemon/api_test.go`

**Step 1: Write the failing test**

Create `linux/daemon/api_test.go`:

```go
package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetchUsage_Success(t *testing.T) {
	payload := UsageResponse{
		FiveHour: &UsageBucket{Utilization: 67.0, ResetsAt: "2026-02-23T18:00:00Z"},
		SevenDay: &UsageBucket{Utilization: 28.0, ResetsAt: "2026-02-25T12:00:00Z"},
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		json.NewEncoder(w).Encode(payload)
	}))
	defer srv.Close()

	client := &APIClient{baseURL: srv.URL + "/"}
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
}

func TestFetchUsage_Unauthorized(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	client := &APIClient{baseURL: srv.URL + "/"}
	_, err := client.fetchUsage("bad-token")
	if err == nil {
		t.Fatal("expected error for 401")
	}
}
```

**Step 2: Run test to verify it fails**

```bash
cd linux/daemon && go test ./... -run TestFetchUsage -v
```
Expected: compile error.

**Step 3: Implement `linux/daemon/api.go`**

```go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// UsageResponse mirrors the Anthropic API response.
type UsageResponse struct {
	FiveHour         *UsageBucket `json:"five_hour"`
	SevenDay         *UsageBucket `json:"seven_day"`
	SevenDaySonnet   *UsageBucket `json:"seven_day_sonnet"`
	SevenDayOauthApps *UsageBucket `json:"seven_day_oauth_apps"`
	SevenDayOpus     *UsageBucket `json:"seven_day_opus"`
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
```

**Step 4: Run tests to verify they pass**

```bash
cd linux/daemon && go test ./... -run TestFetchUsage -v
```
Expected: 2 tests PASS.

**Step 5: Commit**

```bash
git add linux/daemon/api.go linux/daemon/api_test.go
git commit -m "feat(linux/daemon): Anthropic API client"
```

---

## Task 4: Pacing calculator

**Files:**
- Create: `linux/daemon/pacing.go`
- Create: `linux/daemon/pacing_test.go`

**Step 1: Write the failing test**

Create `linux/daemon/pacing_test.go`:

```go
package main

import (
	"testing"
	"time"
)

func TestPacing_Hot(t *testing.T) {
	// 50% elapsed of the week, but 70% used → delta = +20 → hot
	resetsAt := time.Now().Add(84 * time.Hour)   // 3.5 days left → 3.5 / 7 = 50% elapsed
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
}

func TestPacing_OnTrack(t *testing.T) {
	// 50% elapsed, 52% used → delta = +2 → on track
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
```

**Step 2: Run test to verify it fails**

```bash
cd linux/daemon && go test ./... -run TestPacing -v
```
Expected: compile error.

**Step 3: Implement `linux/daemon/pacing.go`**

```go
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
// It compares actual utilization against the expected linear consumption
// for the 7-day window.
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
```

**Step 4: Run tests to verify they pass**

```bash
cd linux/daemon && go test ./... -run TestPacing -v
```
Expected: 3 tests PASS.

**Step 5: Commit**

```bash
git add linux/daemon/pacing.go linux/daemon/pacing_test.go
git commit -m "feat(linux/daemon): pacing calculator (port of PacingCalculator.swift)"
```

---

## Task 5: Notification manager

**Files:**
- Create: `linux/daemon/notifications.go`
- Create: `linux/daemon/notifications_test.go`

**Step 1: Write the failing test**

Create `linux/daemon/notifications_test.go`:

```go
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

func TestNotificationNeeded_NoTransition(t *testing.T) {
	state := &NotificationState{}
	// same level → no notification
	if state.checkTransition("session", LevelGreen) {
		t.Error("should not notify: no level change")
	}
}

func TestNotificationNeeded_Escalation(t *testing.T) {
	state := &NotificationState{}
	// green → orange: should notify
	if !state.checkTransition("session", LevelOrange) {
		t.Error("should notify on green→orange escalation")
	}
	// orange again → no notify (same level)
	if state.checkTransition("session", LevelOrange) {
		t.Error("should not notify: same level")
	}
	// orange → red: should notify
	if !state.checkTransition("session", LevelRed) {
		t.Error("should notify on orange→red escalation")
	}
}

func TestNotificationNeeded_Recovery(t *testing.T) {
	state := &NotificationState{}
	// Advance to red
	state.checkTransition("session", LevelOrange)
	state.checkTransition("session", LevelRed)
	// red → green: should notify (recovery)
	if !state.checkTransition("session", LevelGreen) {
		t.Error("should notify on recovery to green")
	}
}
```

**Step 2: Run test to verify it fails**

```bash
cd linux/daemon && go test ./... -run "TestUsageLevel|TestNotification" -v
```
Expected: compile error.

**Step 3: Implement `linux/daemon/notifications.go`**

```go
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

// NotificationState tracks the last notified level per metric key
// to avoid duplicate notifications.
type NotificationState struct {
	levels map[string]UsageLevel
}

// checkTransition returns true if a notification should be sent,
// and updates the stored level for the metric.
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
	// Notify on escalation or recovery to green
	if current > previous {
		return true
	}
	if current == LevelGreen && previous > LevelGreen {
		return true
	}
	return false
}

// notifier wraps the notification sending logic.
type notifier struct {
	state NotificationState
	// exec is replaceable for testing; defaults to notifySend.
	exec func(summary, body, urgency string) error
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

// CheckThresholds inspects the three main metrics and sends notifications
// if levels have changed.
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
			n.exec(
				fmt.Sprintf("⚠️  %s — %d%%", m.label, pct),
				"Usage is climbing. Consider slowing down.",
				"normal",
			)
		case LevelRed:
			n.exec(
				fmt.Sprintf("🔴 %s — %d%%", m.label, pct),
				"Critical usage — approaching the limit!",
				"critical",
			)
		case LevelGreen:
			n.exec(
				fmt.Sprintf("🟢 %s — %d%%", m.label, pct),
				"Usage reset — you're back in the green.",
				"low",
			)
		}
	}
}
```

**Step 4: Run tests to verify they pass**

```bash
cd linux/daemon && go test ./... -run "TestUsageLevel|TestNotification" -v
```
Expected: all 4 tests PASS.

**Step 5: Commit**

```bash
git add linux/daemon/notifications.go linux/daemon/notifications_test.go
git commit -m "feat(linux/daemon): notification manager (port of UsageNotificationManager.swift)"
```

---

## Task 6: State model (shared D-Bus payload)

**Files:**
- Create: `linux/daemon/state.go`

No tests needed — pure data structure.

**Step 1: Create `linux/daemon/state.go`**

```go
package main

import (
	"encoding/json"
	"time"
)

// DaemonState is the JSON payload emitted on D-Bus and cached on disk.
type DaemonState struct {
	FiveHour       *BucketState  `json:"fiveHour,omitempty"`
	SevenDay       *BucketState  `json:"sevenDay,omitempty"`
	SevenDaySonnet *BucketState  `json:"sevenDaySonnet,omitempty"`
	Pacing         *PacingState  `json:"pacing,omitempty"`
	FetchedAt      time.Time     `json:"fetchedAt"`
	Error          string        `json:"error,omitempty"`
}

type BucketState struct {
	Utilization float64 `json:"utilization"`
	ResetsAt    string  `json:"resetsAt"`
}

type PacingState struct {
	Delta         float64    `json:"delta"`
	Zone          PacingZone `json:"zone"`
	ExpectedUsage float64    `json:"expectedUsage"`
}

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

func (s DaemonState) JSON() string {
	data, _ := json.Marshal(s)
	return string(data)
}
```

**Step 2: Verify compilation**

```bash
cd linux/daemon && go build ./...
```
Expected: no errors.

**Step 3: Commit**

```bash
git add linux/daemon/state.go
git commit -m "feat(linux/daemon): DaemonState — shared D-Bus/JSON payload"
```

---

## Task 7: D-Bus server

**Files:**
- Create: `linux/daemon/dbus.go`

Testing D-Bus requires a real session bus — this is an integration concern. We verify manually.

**Step 1: Create `linux/daemon/dbus.go`**

```go
package main

import (
	"fmt"
	"log"
	"sync"

	dbus "github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

const (
	dbusName      = "io.tokeneater.Daemon"
	dbusPath      = "/io/tokeneater/Daemon"
	dbusInterface = "io.tokeneater.Daemon"
)

// dbusServer exposes the daemon state on the D-Bus session bus.
type dbusServer struct {
	conn  *dbus.Conn
	mu    sync.RWMutex
	state string // JSON
}

func newDBusServer() (*dbusServer, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("connecting to session bus: %w", err)
	}

	reply, err := conn.RequestName(dbusName, dbus.NameFlagDoNotQueue)
	if err != nil {
		return nil, fmt.Errorf("requesting D-Bus name: %w", err)
	}
	if reply != dbus.RequestNameReplyPrimaryOwner {
		return nil, fmt.Errorf("D-Bus name %q already taken", dbusName)
	}

	s := &dbusServer{conn: conn, state: `{}`}

	// Export the object
	conn.Export(s, dbus.ObjectPath(dbusPath), dbusInterface)

	// Export introspection
	node := &introspect.Node{
		Name: dbusPath,
		Interfaces: []introspect.Interface{
			introspect.IntrospectData,
			{
				Name: dbusInterface,
				Methods: []introspect.Method{
					{Name: "GetState", Args: []introspect.Arg{
						{Name: "state", Type: "s", Direction: "out"},
					}},
					{Name: "Refresh"},
				},
				Signals: []introspect.Signal{
					{Name: "StateChanged", Args: []introspect.Arg{
						{Name: "state", Type: "s"},
					}},
				},
			},
		},
	}
	conn.Export(introspect.NewIntrospectable(node), dbus.ObjectPath(dbusPath),
		"org.freedesktop.DBus.Introspectable")

	log.Printf("D-Bus server listening on %s", dbusName)
	return s, nil
}

// GetState is exported as a D-Bus method.
func (s *dbusServer) GetState() (string, *dbus.Error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.state, nil
}

// Refresh is exported as a D-Bus method (triggers immediate fetch in daemon).
// The daemon reads this signal via the refreshCh channel.
func (s *dbusServer) Refresh() *dbus.Error {
	// Non-blocking send — ignored if channel full
	select {
	case s.refreshCh <- struct{}{}:
	default:
	}
	return nil
}

// refreshCh is set by the daemon main loop.
var globalRefreshCh chan struct{}

func (s *dbusServer) setRefreshCh(ch chan struct{}) {
	s.refreshCh = ch
}

// refreshCh field
func init() {
	globalRefreshCh = make(chan struct{}, 1)
}

// emitStateChanged broadcasts the new state to all D-Bus subscribers.
func (s *dbusServer) emitStateChanged(jsonState string) {
	s.mu.Lock()
	s.state = jsonState
	s.mu.Unlock()

	s.conn.Emit(dbus.ObjectPath(dbusPath), dbusInterface+".StateChanged", jsonState)
}

func (s *dbusServer) close() {
	s.conn.Close()
}
```

> **Note:** The `refreshCh` field needs to be added directly to the struct. Refactor the snippet above into a clean struct:

Replace the `dbusServer` definition with:

```go
type dbusServer struct {
	conn      *dbus.Conn
	mu        sync.RWMutex
	state     string
	refreshCh chan struct{}
}
```

And remove the `init()` and `globalRefreshCh` lines — `refreshCh` is set via `setRefreshCh` after construction.

**Step 2: Verify compilation**

```bash
cd linux/daemon && go build ./...
```
Expected: no errors.

**Step 3: Commit**

```bash
git add linux/daemon/dbus.go
git commit -m "feat(linux/daemon): D-Bus server (io.tokeneater.Daemon)"
```

---

## Task 8: Main loop

**Files:**
- Modify: `linux/daemon/main.go`

**Step 1: Replace the stub with the full main loop**

```go
package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const refreshInterval = 5 * time.Minute

func main() {
	log.SetFlags(log.Ltime | log.Lshortfile)
	log.Println("tokeneater-daemon starting")

	credPath := defaultCredentialsPath()
	apiClient := newAPIClient()
	notif := newNotifier()
	refreshCh := make(chan struct{}, 1)

	dbus, err := newDBusServer()
	if err != nil {
		log.Fatalf("D-Bus server: %v", err)
	}
	defer dbus.close()
	dbus.setRefreshCh(refreshCh)

	// Fetch immediately on startup, then on timer or manual refresh.
	fetch := func() {
		log.Println("fetching usage...")
		token, err := readToken(credPath)
		if err != nil {
			log.Printf("token read error: %v", err)
			s := buildState(nil, nil, err)
			dbus.emitStateChanged(s.JSON())
			return
		}

		usage, err := apiClient.fetchUsage(token)
		if err != nil {
			log.Printf("API error: %v", err)
			s := buildState(nil, nil, err)
			dbus.emitStateChanged(s.JSON())
			return
		}

		var pacing *PacingResult
		if usage.SevenDay != nil {
			p, err := calculatePacing(usage.SevenDay)
			if err != nil {
				log.Printf("pacing error: %v", err)
			} else {
				pacing = p
			}
		}

		notif.CheckThresholds(usage)

		s := buildState(usage, pacing, nil)
		dbus.emitStateChanged(s.JSON())
		log.Printf("state updated: session=%.0f%% weekly=%.0f%%",
			func() float64 {
				if usage.FiveHour != nil { return usage.FiveHour.Utilization }
				return 0
			}(),
			func() float64 {
				if usage.SevenDay != nil { return usage.SevenDay.Utilization }
				return 0
			}(),
		)
	}

	// Initial fetch
	fetch()

	ticker := time.NewTicker(refreshInterval)
	defer ticker.Stop()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)

	for {
		select {
		case <-ticker.C:
			fetch()
		case <-refreshCh:
			log.Println("manual refresh requested")
			fetch()
		case sig := <-sigCh:
			log.Printf("received %v, shutting down", sig)
			return
		}
	}
}
```

**Step 2: Verify compilation**

```bash
cd linux/daemon && go build -o /tmp/tokeneater-daemon ./...
```
Expected: binary produced in `/tmp/`.

**Step 3: Quick smoke test — run the daemon**

```bash
/tmp/tokeneater-daemon
```
Expected: logs `fetching usage...`, then either prints usage percentages (if token found and API reachable) or `token read error: ...` (if credentials file missing). Press Ctrl+C to stop.

**Step 4: Commit**

```bash
git add linux/daemon/main.go
git commit -m "feat(linux/daemon): main refresh loop with D-Bus + signals"
```

---

## Task 9: systemd user service

**Files:**
- Create: `linux/tokeneater.service`

**Step 1: Create `linux/tokeneater.service`**

```ini
[Unit]
Description=TokenEater — Claude usage monitor daemon
After=network-online.target graphical-session.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/tokeneater-daemon
Restart=on-failure
RestartSec=30
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus

[Install]
WantedBy=default.target
```

**Step 2: Install and test the service (manual)**

```bash
# Build and install binary
cd linux/daemon && go build -o ~/.local/bin/tokeneater-daemon ./...

# Install service
mkdir -p ~/.config/systemd/user
cp linux/tokeneater.service ~/.config/systemd/user/tokeneater.service

# Enable and start
systemctl --user daemon-reload
systemctl --user enable --now tokeneater
systemctl --user status tokeneater
```
Expected: service shows as `active (running)`.

```bash
journalctl --user -u tokeneater -f
```
Expected: `fetching usage...` log lines every 5 minutes.

**Step 3: Commit**

```bash
git add linux/tokeneater.service
git commit -m "feat(linux): systemd user service for tokeneater-daemon"
```

---

## Task 10: GNOME extension skeleton

**Files:**
- Create: `linux/gnome-extension/metadata.json`
- Create: `linux/gnome-extension/extension.js`
- Create: `linux/gnome-extension/stylesheet.css`

**Step 1: Create `linux/gnome-extension/metadata.json`**

```json
{
  "name": "TokenEater",
  "description": "Monitor your Claude AI usage limits directly from the GNOME status bar.",
  "uuid": "tokeneater-gnome@io.tokeneater",
  "version": 1,
  "shell-version": ["45", "46", "47", "48"],
  "url": "https://github.com/AThevon/TokenEater",
  "settings-schema": ""
}
```

**Step 2: Create `linux/gnome-extension/extension.js`**

```javascript
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import { TokenEaterIndicator } from './panel.js';

export default class TokenEaterExtension extends Extension {
    enable() {
        this._indicator = new TokenEaterIndicator(this);
        // Import Main lazily to avoid circular imports
        const Main = imports.ui.main;
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}
```

**Step 3: Create `linux/gnome-extension/stylesheet.css`**

```css
.tokeneater-label {
    font-size: 12px;
    font-weight: bold;
    padding: 0 4px;
}

.tokeneater-green  { color: #57c758; }
.tokeneater-orange { color: #f5a623; }
.tokeneater-red    { color: #e74c3c; }
.tokeneater-grey   { color: #888888; }

.tokeneater-popup {
    min-width: 280px;
    padding: 8px 0;
}

.tokeneater-metric-row {
    padding: 4px 16px;
}

.tokeneater-metric-label {
    font-size: 11px;
    color: #cccccc;
}

.tokeneater-progress-bg {
    height: 6px;
    background-color: #444444;
    border-radius: 3px;
    margin: 4px 0;
}

.tokeneater-progress-fill {
    height: 6px;
    border-radius: 3px;
    background-color: #57c758;
}

.tokeneater-progress-orange { background-color: #f5a623; }
.tokeneater-progress-red    { background-color: #e74c3c; }

.tokeneater-footer {
    font-size: 10px;
    color: #888888;
    padding: 4px 16px;
}
```

**Step 4: Verify the extension directory structure**

```bash
ls linux/gnome-extension/
```
Expected: `extension.js  metadata.json  stylesheet.css`

**Step 5: Commit**

```bash
git add linux/gnome-extension/
git commit -m "feat(linux/gnome): extension skeleton — metadata, lifecycle, stylesheet"
```

---

## Task 11: D-Bus client (GJS)

**Files:**
- Create: `linux/gnome-extension/dbus.js`

**Step 1: Create `linux/gnome-extension/dbus.js`**

```javascript
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const DBUS_NAME = 'io.tokeneater.Daemon';
const DBUS_PATH = '/io/tokeneater/Daemon';
const DBUS_IFACE = 'io.tokeneater.Daemon';

const DBUS_XML = `
<node>
  <interface name="io.tokeneater.Daemon">
    <method name="GetState">
      <arg name="state" type="s" direction="out"/>
    </method>
    <method name="Refresh"/>
    <signal name="StateChanged">
      <arg name="state" type="s"/>
    </signal>
  </interface>
</node>`;

const DBusProxy = Gio.DBusProxy.makeProxyWrapper(DBUS_XML);

export class TokenEaterDBusClient {
    constructor(onState, onError) {
        this._onState = onState;
        this._onError = onError;
        this._proxy = null;
        this._signalId = null;
        this._retrySource = null;
        this._connect();
    }

    _connect() {
        try {
            this._proxy = new DBusProxy(
                Gio.DBus.session,
                DBUS_NAME,
                DBUS_PATH,
                (proxy, error) => {
                    if (error) {
                        this._onError('TokenEater service not running');
                        this._scheduleRetry();
                        return;
                    }
                    this._subscribeSignal();
                    this._fetchState();
                }
            );
        } catch (e) {
            this._onError('Cannot connect to D-Bus: ' + e.message);
            this._scheduleRetry();
        }
    }

    _subscribeSignal() {
        this._signalId = this._proxy.connectSignal('StateChanged',
            (_proxy, _sender, [jsonState]) => {
                this._onState(JSON.parse(jsonState));
            }
        );
    }

    _fetchState() {
        this._proxy.GetStateRemote((result, error) => {
            if (error) {
                this._onError('Error fetching state: ' + error.message);
                return;
            }
            const [jsonState] = result;
            try {
                this._onState(JSON.parse(jsonState));
            } catch (e) {
                this._onError('Invalid state JSON');
            }
        });
    }

    refresh() {
        if (this._proxy) {
            this._proxy.RefreshRemote(() => {});
        }
    }

    _scheduleRetry() {
        if (this._retrySource) return;
        this._retrySource = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, () => {
            this._retrySource = null;
            this._connect();
            return GLib.SOURCE_REMOVE;
        });
    }

    destroy() {
        if (this._retrySource) {
            GLib.source_remove(this._retrySource);
            this._retrySource = null;
        }
        if (this._proxy && this._signalId) {
            this._proxy.disconnectSignal(this._signalId);
        }
        this._proxy = null;
    }
}
```

**Step 2: Commit**

```bash
git add linux/gnome-extension/dbus.js
git commit -m "feat(linux/gnome): D-Bus client (Gio.DBusProxy wrapper)"
```

---

## Task 12: GNOME panel indicator + popup

**Files:**
- Create: `linux/gnome-extension/panel.js`

**Step 1: Create `linux/gnome-extension/panel.js`**

```javascript
import St from 'gi://St';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import { TokenEaterDBusClient } from './dbus.js';

// ─── Helpers ─────────────────────────────────────────────────────────────────

function colorClass(pct) {
    if (pct >= 85) return 'tokeneater-red';
    if (pct >= 60) return 'tokeneater-orange';
    return 'tokeneater-green';
}

function progressClass(pct) {
    if (pct >= 85) return 'tokeneater-progress-red';
    if (pct >= 60) return 'tokeneater-progress-orange';
    return '';
}

function formatTimeLeft(resetsAtISO) {
    if (!resetsAtISO) return '';
    const now = GLib.get_real_time() / 1_000_000;        // seconds
    const resetsAt = new Date(resetsAtISO).getTime() / 1000;
    const diff = Math.max(0, resetsAt - now);
    const h = Math.floor(diff / 3600);
    const m = Math.floor((diff % 3600) / 60);
    return `Resets in ${h}h ${m}m`;
}

function pacingLabel(pacing) {
    if (!pacing) return '';
    const sign = pacing.delta >= 0 ? '+' : '';
    const emoji = { chill: '😎', onTrack: '✅', hot: '🔥' }[pacing.zone] ?? '';
    return `Pacing: ${emoji} ${sign}${pacing.delta.toFixed(0)}%`;
}

// ─── Metric row (label + progress bar + subtitle) ─────────────────────────────

function makeMetricRow(label, pct, subtitle) {
    const box = new St.BoxLayout({
        vertical: true,
        style_class: 'tokeneater-metric-row',
    });

    const header = new St.Label({
        text: `${label}  ${pct}%`,
        style_class: 'tokeneater-metric-label',
    });
    box.add_child(header);

    const bg = new St.Widget({ style_class: 'tokeneater-progress-bg' });
    const fill = new St.Widget({
        style_class: `tokeneater-progress-fill ${progressClass(pct)}`,
    });
    fill.set_width(Math.round((pct / 100) * 248));   // 248 = popup width - 2*16px padding
    bg.add_child(fill);
    box.add_child(bg);

    if (subtitle) {
        const sub = new St.Label({
            text: subtitle,
            style_class: 'tokeneater-footer',
        });
        box.add_child(sub);
    }

    return box;
}

// ─── Indicator ────────────────────────────────────────────────────────────────

export class TokenEaterIndicator extends PanelMenu.Button {
    constructor(extension) {
        super(0.0, 'TokenEater');
        this._extension = extension;

        // Status bar label
        this._label = new St.Label({
            text: '◉ …',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'tokeneater-label tokeneater-grey',
        });
        this.add_child(this._label);

        // Popup content container
        this._popupBox = null;
        this._buildPopup();

        // D-Bus client
        this._dbus = new TokenEaterDBusClient(
            (state) => this._onState(state),
            (msg)   => this._onError(msg),
        );
    }

    // ── Popup skeleton ─────────────────────────────────────────────────────────

    _buildPopup() {
        this._contentItem = new PopupMenu.PopupBaseMenuItem({ reactive: false });
        this._popupBox = new St.BoxLayout({
            vertical: true,
            style_class: 'tokeneater-popup',
        });
        this._contentItem.add_child(this._popupBox);
        this.menu.addMenuItem(this._contentItem);

        // Separator + footer row
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const footerItem = new PopupMenu.PopupBaseMenuItem({ reactive: false });
        this._footerLabel = new St.Label({
            text: '',
            style_class: 'tokeneater-footer',
            x_expand: true,
        });
        this._refreshBtn = new St.Button({
            label: 'Refresh',
            style_class: 'button',
        });
        this._refreshBtn.connect('clicked', () => this._dbus.refresh());
        footerItem.add_child(this._footerLabel);
        footerItem.add_child(this._refreshBtn);
        this.menu.addMenuItem(footerItem);
    }

    _clearPopupBox() {
        if (this._popupBox) {
            this._popupBox.destroy_all_children();
        }
    }

    // ── State update ───────────────────────────────────────────────────────────

    _onState(state) {
        this._clearPopupBox();

        if (state.error) {
            this._setLabel('◉ ?', 'tokeneater-grey');
            this._popupBox.add_child(new St.Label({
                text: `Error: ${state.error}`,
                style_class: 'tokeneater-footer',
            }));
            return;
        }

        // Top bar label
        const sessionPct = state.fiveHour?.utilization ?? 0;
        this._setLabel(`◉ ${Math.round(sessionPct)}%`, colorClass(sessionPct));

        // Session row
        if (state.fiveHour) {
            this._popupBox.add_child(makeMetricRow(
                'Session (5h)',
                Math.round(state.fiveHour.utilization),
                formatTimeLeft(state.fiveHour.resetsAt),
            ));
        }

        // Weekly row
        if (state.sevenDay) {
            this._popupBox.add_child(makeMetricRow(
                'Weekly — All',
                Math.round(state.sevenDay.utilization),
                formatTimeLeft(state.sevenDay.resetsAt),
            ));
        }

        // Sonnet row
        if (state.sevenDaySonnet) {
            this._popupBox.add_child(makeMetricRow(
                'Weekly — Sonnet',
                Math.round(state.sevenDaySonnet.utilization),
                null,
            ));
        }

        // Pacing label
        if (state.pacing) {
            this._popupBox.add_child(new St.Label({
                text: pacingLabel(state.pacing),
                style_class: 'tokeneater-metric-label',
                style: 'padding: 8px 16px 4px;',
            }));
        }

        // Footer timestamp
        if (state.fetchedAt) {
            const d = new Date(state.fetchedAt);
            this._footerLabel.text = `Last: ${d.getHours().toString().padStart(2,'0')}:${d.getMinutes().toString().padStart(2,'0')}`;
        }
    }

    _onError(msg) {
        this._setLabel('◉ !', 'tokeneater-grey');
        this._clearPopupBox();
        this._popupBox.add_child(new St.Label({
            text: msg,
            style_class: 'tokeneater-footer',
            style: 'padding: 8px 16px;',
        }));
    }

    _setLabel(text, cls) {
        this._label.text = text;
        for (const c of ['tokeneater-green', 'tokeneater-orange', 'tokeneater-red', 'tokeneater-grey']) {
            this._label.remove_style_class_name(c);
        }
        this._label.add_style_class_name(cls);
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    destroy() {
        if (this._dbus) {
            this._dbus.destroy();
            this._dbus = null;
        }
        super.destroy();
    }
}
```

**Step 2: Commit**

```bash
git add linux/gnome-extension/panel.js
git commit -m "feat(linux/gnome): panel indicator + popup menu (D-Bus reactive UI)"
```

---

## Task 13: Install and smoke test

**Step 1: Build and install the daemon**

```bash
cd linux/daemon && go build -o ~/.local/bin/tokeneater-daemon ./...
chmod +x ~/.local/bin/tokeneater-daemon
```

**Step 2: Install the GNOME extension**

```bash
EXT_DIR=~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater
mkdir -p "$EXT_DIR"
cp -r linux/gnome-extension/. "$EXT_DIR/"
```

**Step 3: Install and start the systemd service**

```bash
mkdir -p ~/.config/systemd/user
cp linux/tokeneater.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tokeneater
systemctl --user status tokeneater
```
Expected: `active (running)`.

**Step 4: Check daemon logs**

```bash
journalctl --user -u tokeneater -n 20
```
Expected: `fetching usage...` and a state update with session/weekly percentages.

**Step 5: Enable the GNOME extension**

```bash
gnome-extensions enable tokeneater-gnome@io.tokeneater
```
If the extension doesn't appear immediately, log out and back in, or run:
```bash
gnome-shell --replace &
```
(Only on X11; on Wayland, full logout is required to reload extensions.)

**Step 6: Verify in GNOME**

- Look at the top bar right side → should see `◉ XX%` in green/orange/red
- Click the indicator → popup shows Session, Weekly, Sonnet progress bars + pacing
- Click Refresh → indicator updates within a few seconds

**Step 7: Test notifications (optional)**

Temporarily lower the threshold in `notifications.go` to 1% to trigger a notification without using up quota:
```go
// In usageLevelFrom, temporarily:
case pct >= 1:
    return LevelOrange
```
Rebuild, restart service, verify `notify-send` notification appears.

**Step 8: Commit smoke test confirmation**

```bash
git commit --allow-empty -m "test(linux): smoke test passed — daemon + GNOME extension working"
```

---

## Task 14: Linux README

**Files:**
- Create: `linux/README.md`

**Step 1: Create `linux/README.md`**

```markdown
# TokenEater — Linux / GNOME

Monitor your Claude AI usage limits from the GNOME Shell status bar.

## Requirements

- Ubuntu 22.04+ / Fedora 38+ (any GNOME 45+)
- Claude Code installed and authenticated (`claude /login`)
- Go 1.22+ (to build from source)
- `notify-send` (`apt install libnotify-bin`)

## Build & Install (from source)

```bash
# Build daemon
cd linux/daemon
go build -o ~/.local/bin/tokeneater-daemon ./...

# Install GNOME extension
EXT=~/.local/share/gnome-shell/extensions/tokeneater-gnome@io.tokeneater
mkdir -p "$EXT"
cp -r linux/gnome-extension/. "$EXT/"

# Install systemd user service
cp linux/tokeneater.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tokeneater

# Enable extension (log out/in on Wayland to take effect)
gnome-extensions enable tokeneater-gnome@io.tokeneater
```

## Architecture

See `docs/plans/2026-02-23-linux-gnome-design.md` for the full design.

- **`daemon/`** — Go service: reads `~/.claude/.credentials.json`, calls the Anthropic API,
  exposes data via D-Bus (`io.tokeneater.Daemon`), sends `notify-send` alerts.
- **`gnome-extension/`** — GNOME Shell extension (GJS): subscribes to D-Bus signals,
  renders usage in the status bar, detailed popup on click.
- **`tokeneater.service`** — systemd user service (auto-starts with your session).

## Supported metrics

| Metric | Source |
|--------|--------|
| Session (5h) | `five_hour` bucket |
| Weekly — All | `seven_day` bucket |
| Weekly — Sonnet | `seven_day_sonnet` bucket |
| Pacing | computed from `seven_day` elapsed time |

## Notifications

Threshold transitions trigger a desktop notification:

| Level | Threshold |
|-------|-----------|
| 🟠 Warning | ≥ 60% |
| 🔴 Critical | ≥ 85% |
| 🟢 Recovery | back to < 60% |
```

**Step 2: Commit**

```bash
git add linux/README.md
git commit -m "docs(linux): installation and architecture README"
```

---

## Done

All tasks complete. The implementation delivers:

1. **Go daemon** — token reader, API client, pacing, notifications, D-Bus server, 5-min refresh loop, systemd service
2. **GNOME extension** — reactive status bar indicator + detailed popup
3. **Tests** — unit tests for token reader, API client, pacing calculator, notification state machine
4. **Docs** — Linux README
