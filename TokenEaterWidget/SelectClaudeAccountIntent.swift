import AppIntents
import AppKit
import WidgetKit

/// The configuration of the "Claude · Account" widget: which tracked Claude
/// account it shows, picked in Edit Widget. Two copies of the widget can show
/// two accounts. Left unset, it shows the main account.
struct SelectClaudeAccountIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.account.intent.title"
    static var description = IntentDescription("widget.account.intent.description")

    @Parameter(title: "widget.account.intent.parameter")
    var account: ClaudeAccountEntity?
}

/// A tracked Claude account as the widget's picker lists it. Built from the
/// accounts index in `shared.json` alone: a local identifier, the name and
/// colour the user chose, whether it is paused. No email, no organization.
struct ClaudeAccountEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.account.entity")
    static var defaultQuery = ClaudeAccountQuery()

    /// `AccountID.rawValue`.
    let id: String
    let name: String
    let colorHex: String
    let isMain: Bool
    let isPaused: Bool
    /// The widget was set to an account that is no longer tracked. Kept as
    /// the selection so the widget says so instead of switching to another
    /// account behind the user's back.
    let isRemoved: Bool

    init(_ entry: AccountIndexEntry) {
        id = entry.id
        name = entry.name
        colorHex = entry.colorHex
        isMain = entry.isMain
        isPaused = entry.isPaused && !entry.isMain
        isRemoved = false
    }

    private init(removedID: String) {
        id = removedID
        name = String(localized: "widget.account.removed.title")
        colorHex = AccountPalette.slate
        isMain = false
        isPaused = false
        isRemoved = true
    }

    static func removed(id: String) -> ClaudeAccountEntity {
        ClaudeAccountEntity(removedID: id)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle,
            image: isRemoved ? nil : Self.dotImage(colorHex: colorHex)
        )
    }

    private var subtitle: LocalizedStringResource? {
        if isRemoved { return "widget.account.removed.short" }
        if isPaused { return "widget.account.paused" }
        if isMain { return "widget.account.main" }
        return nil
    }

    /// The account's colour dot, for pickers that show an image next to the
    /// name. Drawn into a bitmap, no window server involved.
    private static func dotImage(colorHex: String) -> DisplayRepresentation.Image? {
        let side = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(hex: colorHex).setFill()
        NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: side - 12, height: side - 12)).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return DisplayRepresentation.Image(data: png)
    }
}

/// Lists the tracked accounts from the accounts index, main first. With no
/// index written (one untouched account) that is the main account alone.
struct ClaudeAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ClaudeAccountEntity] {
        let index = Self.currentIndex()
        return identifiers.compactMap { id in
            if let entry = AccountIndexEntry.resolve(id, in: index) {
                return ClaudeAccountEntity(entry)
            }
            // A removed account stays the selection, flagged, as long as its
            // identifier is one the app could have written.
            return AccountID.isValid(id) ? .removed(id: id) : nil
        }
    }

    func suggestedEntities() async throws -> [ClaudeAccountEntity] {
        AccountIndexEntry.effectiveIndex(Self.currentIndex()).map(ClaudeAccountEntity.init)
    }

    func defaultResult() async -> ClaudeAccountEntity? {
        AccountIndexEntry.resolve(nil, in: Self.currentIndex()).map(ClaudeAccountEntity.init)
    }

    private static func currentIndex() -> [AccountIndexEntry] {
        SharedFileService().accountsIndex ?? []
    }
}
