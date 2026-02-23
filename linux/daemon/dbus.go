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
	conn      *dbus.Conn
	mu        sync.RWMutex
	state     string
	refreshCh chan struct{}
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

	conn.Export(s, dbus.ObjectPath(dbusPath), dbusInterface)

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

// Refresh is exported as a D-Bus method — triggers an immediate fetch cycle.
func (s *dbusServer) Refresh() *dbus.Error {
	if s.refreshCh != nil {
		select {
		case s.refreshCh <- struct{}{}:
		default:
		}
	}
	return nil
}

// setRefreshCh wires the daemon's refresh channel into the D-Bus server.
func (s *dbusServer) setRefreshCh(ch chan struct{}) {
	s.refreshCh = ch
}

// emitStateChanged stores the new state and broadcasts it to D-Bus subscribers.
func (s *dbusServer) emitStateChanged(jsonState string) {
	s.mu.Lock()
	s.state = jsonState
	s.mu.Unlock()

	s.conn.Emit(dbus.ObjectPath(dbusPath), dbusInterface+".StateChanged", jsonState)
}

func (s *dbusServer) close() {
	s.conn.Close()
}
