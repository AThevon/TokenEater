// GNOME 42-compatible panel indicator for TokenEater.
// Uses imports.gi.* and imports.ui.* (compatible with GNOME 42-48).

const { St, GLib, Clutter } = imports.gi;
const PanelMenu = imports.ui.panelMenu;
const PopupMenu = imports.ui.popupMenu;
const Me = imports.misc.extensionUtils.getCurrentExtension();
const { TokenEaterDBusClient } = Me.imports.dbus;

// ─── Helpers ──────────────────────────────────────────────────────────────────

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
    const now     = GLib.get_real_time() / 1_000_000; // seconds
    const resetsAt = new Date(resetsAtISO).getTime() / 1000;
    const diff    = Math.max(0, resetsAt - now);
    const h = Math.floor(diff / 3600);
    const m = Math.floor((diff % 3600) / 60);
    return `Resets in ${h}h ${m}m`;
}

function pacingLabel(pacing) {
    if (!pacing) return '';
    const sign  = pacing.delta >= 0 ? '+' : '';
    const emoji = { chill: '😎', onTrack: '✅', hot: '🔥' }[pacing.zone] || '';
    return `Pacing: ${emoji} ${sign}${pacing.delta.toFixed(0)}%`;
}

// ─── Metric row (label + progress bar + optional subtitle) ────────────────────

function makeMetricRow(label, pct, subtitle) {
    const box = new St.BoxLayout({ vertical: true, style_class: 'tokeneater-metric-row' });

    box.add_child(new St.Label({
        text: `${label}  ${pct}%`,
        style_class: 'tokeneater-metric-label',
    }));

    const bg   = new St.Widget({ style_class: 'tokeneater-progress-bg' });
    const fill = new St.Widget({
        style_class: `tokeneater-progress-fill ${progressClass(pct)}`,
        width: Math.round((pct / 100) * 248),
    });
    bg.add_child(fill);
    box.add_child(bg);

    if (subtitle) {
        box.add_child(new St.Label({ text: subtitle, style_class: 'tokeneater-footer' }));
    }

    return box;
}

// ─── Indicator ────────────────────────────────────────────────────────────────

var TokenEaterIndicator = class TokenEaterIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.0, 'TokenEater');
        this._extension = extension;

        // Status bar label
        this._label = new St.Label({
            text: '◉ …',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'tokeneater-label tokeneater-grey',
        });
        this.add_child(this._label);

        this._buildPopup();

        this._dbus = new TokenEaterDBusClient(
            (state) => this._onState(state),
            (msg)   => this._onError(msg),
        );
    }

    // ── Popup skeleton ──────────────────────────────────────────────────────────

    _buildPopup() {
        this._contentItem = new PopupMenu.PopupBaseMenuItem({ reactive: false });
        this._popupBox = new St.BoxLayout({ vertical: true, style_class: 'tokeneater-popup' });
        this._contentItem.add_child(this._popupBox);
        this.menu.addMenuItem(this._contentItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const footerItem = new PopupMenu.PopupBaseMenuItem({ reactive: false });
        this._footerLabel = new St.Label({
            text: '',
            style_class: 'tokeneater-footer',
            x_expand: true,
        });
        this._refreshBtn = new St.Button({ label: 'Refresh', style_class: 'button' });
        this._refreshBtn.connect('clicked', () => this._dbus.refresh());
        footerItem.add_child(this._footerLabel);
        footerItem.add_child(this._refreshBtn);
        this.menu.addMenuItem(footerItem);
    }

    _clearPopupBox() {
        if (this._popupBox)
            this._popupBox.destroy_all_children();
    }

    // ── State update ────────────────────────────────────────────────────────────

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

        const sessionPct = state.fiveHour ? Math.round(state.fiveHour.utilization) : 0;
        this._setLabel(`◉ ${sessionPct}%`, colorClass(sessionPct));

        if (state.fiveHour) {
            this._popupBox.add_child(makeMetricRow(
                'Session (5h)',
                Math.round(state.fiveHour.utilization),
                formatTimeLeft(state.fiveHour.resetsAt),
            ));
        }

        if (state.sevenDay) {
            this._popupBox.add_child(makeMetricRow(
                'Weekly — All',
                Math.round(state.sevenDay.utilization),
                formatTimeLeft(state.sevenDay.resetsAt),
            ));
        }

        if (state.sevenDaySonnet) {
            this._popupBox.add_child(makeMetricRow(
                'Weekly — Sonnet',
                Math.round(state.sevenDaySonnet.utilization),
                null,
            ));
        }

        if (state.pacing) {
            this._popupBox.add_child(new St.Label({
                text: pacingLabel(state.pacing),
                style_class: 'tokeneater-metric-label',
                style: 'padding: 8px 16px 4px;',
            }));
        }

        if (state.fetchedAt) {
            const d = new Date(state.fetchedAt);
            const hh = String(d.getHours()).padStart(2, '0');
            const mm = String(d.getMinutes()).padStart(2, '0');
            this._footerLabel.text = `Last: ${hh}:${mm}`;
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
        for (const c of ['tokeneater-green', 'tokeneater-orange', 'tokeneater-red', 'tokeneater-grey'])
            this._label.remove_style_class_name(c);
        this._label.add_style_class_name(cls);
    }

    // ── Lifecycle ───────────────────────────────────────────────────────────────

    destroy() {
        if (this._dbus) {
            this._dbus.destroy();
            this._dbus = null;
        }
        super.destroy();
    }
};
