import SwiftUI
import WidgetKit

// =====================================================================
// MARK: - Extra Credits (Small + Medium)
//
// Dedicated widget for the paid Extra Credits pool, for accounts (e.g.
// Enterprise) whose primary signal is overage spend rather than the
// 5h / 7d quotas. The pool has no reset window, so colouring is purely
// threshold-based (no Smart Color risk model).
// =====================================================================

struct ExtraCreditsWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) var family
    private var theme: ThemeColors { WidgetTheme.theme }
    private var thresholds: UsageThresholds { WidgetTheme.thresholds }

    var body: some View {
        Group {
            if entry.error != nil, entry.usage == nil {
                ErrorContent(message: entry.error ?? String(localized: "error.nodata"))
            } else if let extra = entry.usage?.extraUsage, extra.isEnabled {
                switch family {
                case .systemMedium: mediumContent(extra)
                default: smallContent(extra)
                }
            } else if entry.usage != nil {
                // Connected, but the pool isn't provisioned/enabled for this
                // account. Say so explicitly rather than showing a fake 0%.
                disabledContent
            } else {
                PlaceholderContent()
            }
        }
        .widgetURL(URL(string: "tokeneater://open"))
        .modifier(WidgetBackgroundModifier())
    }

    // MARK: - Small : hero ring + spend

    private func smallContent(_ extra: ExtraUsage) -> some View {
        let pct = extra.percent
        let color = theme.gaugeColor(for: Double(pct), thresholds: thresholds)
        let gradient = theme.gaugeGradient(for: Double(pct), thresholds: thresholds)

        return VStack(spacing: 0) {
            WidgetHeader("widget.extra")
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .stroke(.white.opacity(WidgetTokens.trackOpacity), lineWidth: WidgetTokens.ringSmall)
                Circle()
                    .trim(from: 0, to: min(Double(pct), 100) / 100)
                    .stroke(gradient, style: StrokeStyle(lineWidth: WidgetTokens.ringSmall, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.32), radius: 5)
                HeroPercent(pct)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            Spacer(minLength: 8)
            Text(amountText(extra))
                .font(WidgetTokens.microMono)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Medium : hero number + bar + spend

    private func mediumContent(_ extra: ExtraUsage) -> some View {
        let pct = extra.percent
        let color = theme.gaugeColor(for: Double(pct), thresholds: thresholds)
        let gradient = theme.gaugeGradient(
            for: Double(pct), thresholds: thresholds, startPoint: .leading, endPoint: .trailing
        )

        return VStack(alignment: .leading, spacing: 10) {
            WidgetHeader("widget.extra")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(pct)%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color.opacity(0.85))
                    .baselineOffset(2)
                Spacer(minLength: 0)
                Text(amountText(extra))
                    .font(WidgetTokens.bodyMono)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(WidgetTokens.trackOpacity))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gradient)
                        .frame(width: max(0, geo.size.width * min(Double(pct), 100) / 100))
                }
            }
            .frame(height: 6)

            Spacer(minLength: 0)

            Text("dashboard.extra.monthly")
                .font(WidgetTokens.micro)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
        }
    }

    // MARK: - Disabled state

    private var disabledContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
            Text("widget.extra.disabled")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helpers

    /// "$180 / $500" with a limit, otherwise just the spend ("$180").
    private func amountText(_ extra: ExtraUsage) -> String {
        let used = CurrencyFormatter.formatMinorUnits(extra.usedCredits ?? 0, currencyCode: extra.currency)
        guard let limit = extra.monthlyLimit, limit > 0 else { return used }
        return "\(used) / \(CurrencyFormatter.formatMinorUnits(limit, currencyCode: extra.currency))"
    }
}
