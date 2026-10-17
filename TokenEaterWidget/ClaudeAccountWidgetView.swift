import SwiftUI
import WidgetKit

// MARK: - Account in the environment

/// The account a "Claude · Account" widget shows, as its views need it: the
/// name and colour the user chose, and whether the account is paused.
struct WidgetAccountBadge: Equatable {
    let name: String
    let colorHex: String
    let isPaused: Bool

    init(_ entry: AccountIndexEntry) {
        name = entry.name
        colorHex = entry.colorHex
        isPaused = entry.isPaused && !entry.isMain
    }

    /// How far a paused account's numbers recede.
    static let pausedOpacity: Double = 0.5
}

private struct WidgetAccountKey: EnvironmentKey {
    static let defaultValue: WidgetAccountBadge? = nil
}

extension EnvironmentValues {
    /// Set by the account widget around the real widget views, which then
    /// name the account in their header (`WidgetHeader`) and dim a paused
    /// one (`WidgetBackgroundModifier`). Nil in every other widget.
    var widgetAccount: WidgetAccountBadge? {
        get { self[WidgetAccountKey.self] }
        set { self[WidgetAccountKey.self] = newValue }
    }
}

// MARK: - Header title

/// What `WidgetHeader` draws in the account widget in place of the logo and
/// label: the account's dot and name, then the view's own label, dimmer.
/// When both do not fit (a long name in the small family) the label goes
/// first and the name is kept; a paused account says so instead of the label.
struct AccountWidgetHeaderTitle: View {
    let account: WidgetAccountBadge
    let label: LocalizedStringKey

    private var textColor: Color { Color(hex: WidgetTheme.theme.widgetText) }

    var body: some View {
        HStack(spacing: 5) {
            AccountDot(colorHex: account.colorHex, size: 8)
                .frame(width: 12, height: 12)
            if account.isPaused {
                HStack(spacing: 4) {
                    name.layoutPriority(0)
                    styled(Text("widget.account.paused"), opacity: WidgetTokens.primary)
                        .fixedSize()
                        .layoutPriority(1)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        name.fixedSize()
                        styled(Text(label), opacity: WidgetTokens.tertiary).fixedSize()
                    }
                    name
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        styled(Text(verbatim: account.name), opacity: WidgetTokens.primary)
            .truncationMode(.tail)
    }

    private func styled(_ text: Text, opacity: Double) -> some View {
        text
            .font(WidgetTokens.header)
            .tracking(WidgetTokens.headerTracking)
            .foregroundStyle(textColor.opacity(opacity))
            .textCase(.uppercase)
            .lineLimit(1)
    }
}

// MARK: - Widget view

/// The "Claude · Account" widget: the real Session Ring (small) and Claude
/// Overview (medium) views, reading the chosen account's numbers, with the
/// account named in their header.
struct ClaudeAccountWidgetView: View {
    let entry: ClaudeAccountEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.state {
        case .removed:
            AccountWidgetMessage(
                icon: "person.crop.circle.badge.xmark",
                title: "widget.account.removed.title",
                message: String(localized: "widget.account.removed.body")
            )
        case .active(let account), .paused(let account):
            Group {
                if entry.usage.usage != nil {
                    switch family {
                    case .systemSmall:
                        SessionRingWidgetView(entry: entry.usage)
                    default:
                        UsageWidgetView(entry: entry.usage)
                    }
                } else if entry.state == .paused(account) {
                    AccountWidgetMessage(
                        icon: "pause.circle",
                        title: "widget.account.paused.empty.title",
                        message: String(localized: "widget.account.paused.empty.body")
                    )
                } else {
                    AccountWidgetMessage(
                        icon: "hourglass",
                        title: "widget.account.waiting.title",
                        message: entry.usage.error ?? String(localized: "widget.account.waiting.body")
                    )
                }
            }
            .environment(\.widgetAccount, WidgetAccountBadge(account))
        }
    }
}

/// A state with no numbers to show: an icon, a short title and what to do,
/// under the same header as the numbers would have.
struct AccountWidgetMessage: View {
    let icon: String
    let title: LocalizedStringKey
    let message: String

    @Environment(\.widgetFamily) private var family
    private var textColor: Color { Color(hex: WidgetTheme.theme.widgetText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader("widget.title.usage")
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: family == .systemSmall ? 20 : 22, weight: .semibold))
                    .foregroundStyle(textColor.opacity(WidgetTokens.secondary))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textColor.opacity(WidgetTokens.primary))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(WidgetTokens.micro)
                    .foregroundStyle(textColor.opacity(WidgetTokens.secondary))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 6)
        }
        .padding(.horizontal, WidgetTokens.outerPadding)
        .widgetURL(URL(string: "tokeneater://open"))
        .modifier(WidgetBackgroundModifier())
    }
}
