// GNOME 42-compatible extension entry point.
// Uses the classic enable()/disable() function pattern with extensionUtils.

const Main = imports.ui.main;
const ExtensionUtils = imports.misc.extensionUtils;
const Me = ExtensionUtils.getCurrentExtension();
const { TokenEaterIndicator } = Me.imports.panel;

let _indicator = null;

function init() {
    // Nothing to do on init for this extension.
}

function enable() {
    _indicator = new TokenEaterIndicator(Me);
    Main.panel.addToStatusArea(Me.uuid, _indicator);
}

function disable() {
    if (_indicator) {
        _indicator.destroy();
        _indicator = null;
    }
}
