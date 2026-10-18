import Foundation

/// Reads the preferences a build of the second-account prototype (#284)
/// left behind into what this build understands, before any store reads
/// them.
///
/// That build had a `claudeWork` provider mode, `work*` menu bar segments
/// and popover elements mirroring the Claude ones, an `extraClaudeAccounts`
/// list it filled by itself from the Keychain, and a few keys of its own.
/// None of it has a meaning here, where a second account is one the user
/// connects from its config folder. So:
///
/// - the `claudeWork` mode becomes All, and the layouts stored for it go;
/// - `work*` segments and elements are dropped from every stored layout and
///   saved template (the rest of each layout stays as it was). The lossy
///   decoders would drop them on read anyway; rewriting the blobs keeps them
///   from coming back as soon as a decode is not lossy;
/// - the prototype's account list and its own keys go. Nothing is read from
///   the Keychain and no account is added: its second login is connected
///   again from Settings > Providers, explicitly.
///
/// Idempotent and silent on an install that never ran the prototype: it
/// reads a handful of keys and writes nothing.
enum PrototypeAccountMigration {
    static let modeRawValue = "claudeWork"
    static let workKinds = ["workSession", "workWeekly", "workSessionPacing", "workWeeklyPacing"]
    /// The prototype's own keys, all dropped.
    static let obsoleteKeys = ["extraClaudeAccounts", "workAccountLabel", "workAccountMenuBarSeeded"]

    /// Returns whether anything was changed.
    @discardableResult
    static func run(defaults: UserDefaults = .standard) -> Bool {
        var changed = false

        if defaults.string(forKey: "activeProviderMode") == modeRawValue {
            defaults.set(ProviderMode.all.rawValue, forKey: "activeProviderMode")
            changed = true
        }

        let keys = Array(defaults.dictionaryRepresentation().keys)
        for key in keys where obsoleteKeys.contains(key) || isObsoleteSuffixed(key) {
            defaults.removeObject(forKey: key)
            changed = true
        }

        if let data = defaults.data(forKey: "heroWindows"),
           var windows = try? JSONDecoder().decode([String: String].self, from: data),
           windows.removeValue(forKey: modeRawValue) != nil,
           let encoded = try? JSONEncoder().encode(windows) {
            defaults.set(encoded, forKey: "heroWindows")
            changed = true
        }

        for key in keys where isLayoutKey(key) {
            guard let data = defaults.data(forKey: key), mentionsWorkKind(data) else { continue }
            if let rewritten = withoutWorkKinds(data, key: key) {
                defaults.set(rewritten, forKey: key)
            } else {
                // Unreadable even lossily: the store would fall back to its
                // seeded layout for this key anyway.
                defaults.removeObject(forKey: key)
            }
            changed = true
        }
        return changed
    }

    /// The layouts stored for the `claudeWork` mode, and the pacing samples
    /// of its second store (`sessionPacingSamples.<service suffix>`); this
    /// build's own per-account keys end in `.acct-<id>`.
    static func isObsoleteSuffixed(_ key: String) -> Bool {
        if key.hasSuffix("." + modeRawValue) { return true }
        let samples = "sessionPacingSamples."
        return key.hasPrefix(samples) && !key.dropFirst(samples.count).hasPrefix("acct-")
    }

    static func isLayoutKey(_ key: String) -> Bool {
        key == "popoverUserTemplates" || key == "menuBarUserTemplates"
            || key == "popoverComposition" || key.hasPrefix("popoverComposition.")
            || key == "menuBarComposition" || key.hasPrefix("menuBarComposition.")
    }

    /// A cheap test on the raw JSON, so layouts the prototype never touched
    /// are not decoded at every launch.
    static func mentionsWorkKind(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return workKinds.contains { text.contains("\"" + $0 + "\"") }
    }

    /// The blob decoded with the lossy decoders, which drop every kind this
    /// build does not know, and encoded again.
    private static func withoutWorkKinds(_ data: Data, key: String) -> Data? {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        switch key {
        case "popoverUserTemplates":
            return (try? decoder.decode([PopoverUserTemplate].self, from: data)).flatMap { try? encoder.encode($0) }
        case "menuBarUserTemplates":
            return (try? decoder.decode([MenuBarUserTemplate].self, from: data)).flatMap { try? encoder.encode($0) }
        case let key where key.hasPrefix("popoverComposition"):
            return (try? decoder.decode(PopoverComposition.self, from: data)).flatMap { try? encoder.encode($0) }
        default:
            return (try? decoder.decode(MenuBarComposition.self, from: data)).flatMap { try? encoder.encode($0) }
        }
    }
}
