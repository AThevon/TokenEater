// GNOME 42-compatible D-Bus client for the TokenEater daemon.
// Uses imports.gi.* (legacy module system, compatible with GNOME 42-44).
// For GNOME 45+, the same code works because GNOME 45 keeps backward compat for extensions.

const { Gio, GLib } = imports.gi;

const DBUS_NAME  = 'io.tokeneater.Daemon';
const DBUS_PATH  = '/io/tokeneater/Daemon';

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

var TokenEaterDBusClient = class TokenEaterDBusClient {
    constructor(onState, onError) {
        this._onState    = onState;
        this._onError    = onError;
        this._proxy      = null;
        this._signalId   = null;
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
                try {
                    this._onState(JSON.parse(jsonState));
                } catch (e) {
                    this._onError('Invalid state JSON from signal');
                }
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
        if (this._proxy)
            this._proxy.RefreshRemote(() => {});
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
            this._signalId = null;
        }
        this._proxy = null;
    }
};
