import SwiftUI

/// Pacing logic settings: Smart Color (how usage maps to gauge colour and
/// severity), pacing sensitivity, and the workweek schedule (active days +
/// hours). Split out of Themes so that section stays purely about the colour
/// palette and visual style, while this one owns the risk/pace behaviour.
struct PacingSectionView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var showSmartColorPopover = false
    @State private var showWorkweekPopover = false
    @State private var warningSlider: Double
    @State private var criticalSlider: Double
    @State private var marginSlider: Double

    init(initialWarning: Int, initialCritical: Int, initialMargin: Int) {
        _warningSlider = State(initialValue: Double(initialWarning))
        _criticalSlider = State(initialValue: Double(initialCritical))
        _marginSlider = State(initialValue: Double(initialMargin))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                String(localized: "sidebar.pacing"),
                subtitle: String(localized: "sidebar.pacing.subtitle")
            )

            // Smart Color (global toggle, drives gauges + countdowns coloring)
            glassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                cardLabel(String(localized: "settings.smartcolor.title"))
                                Button {
                                    showSmartColorPopover.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showSmartColorPopover, arrowEdge: .bottom) {
                                    smartColorInfoPopover
                                        .background(DS.Palette.bgElevated)
                                        .preferredColorScheme(.dark)
                                }
                            }
                            Text(String(localized: "settings.smartcolor.hint"))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $settingsStore.smartColorEnabled)
                            .toggleStyle(.switch)
                            .tint(DS.Palette.accentSettings)
                            .labelsHidden()
                    }

                    if settingsStore.smartColorEnabled {
                        smartColorProfilePicker
                    }
                }
            }

            // Thresholds (only relevant when Smart Color is OFF: smart mode
            // owns its own calibration via the chosen profile).
            if !settingsStore.smartColorEnabled {
                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardLabel(String(localized: "settings.theme.thresholds"))
                        thresholdSlider(label: String(localized: "settings.theme.warning"), value: $warningSlider, range: 10...90)
                        thresholdSlider(label: String(localized: "settings.theme.critical"), value: $criticalSlider, range: 15...95)

                        Text(String(localized: "settings.theme.thresholds.hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)

                        HStack(spacing: 24) {
                            Spacer()
                            themePreviewGauge(pct: Double(max(themeStore.warningThreshold - 15, 5)), label: "Normal")
                            themePreviewGauge(pct: Double(themeStore.warningThreshold + themeStore.criticalThreshold) / 2.0, label: "Warning")
                            themePreviewGauge(pct: Double(min(themeStore.criticalThreshold + 5, 100)), label: "Critical")
                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                }
            }

            // Pacing sensitivity (margin)
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.pacing.margin"))
                    thresholdSlider(label: String(localized: "settings.pacing.margin.value"), value: $marginSlider, range: 5...30)
                    pacingZonesPreview
                    Text(String(localized: "settings.pacing.margin.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Workweek pacing
            workweekCard

            Spacer()
        }
        .padding(24)
        .onChange(of: warningSlider) { _, new in
            let int = Int(new)
            if themeStore.warningThreshold != int { themeStore.warningThreshold = int }
            if int >= themeStore.criticalThreshold { themeStore.criticalThreshold = min(int + 5, 95) }
        }
        .onChange(of: criticalSlider) { _, new in
            let int = Int(new)
            if themeStore.criticalThreshold != int { themeStore.criticalThreshold = int }
            if int <= themeStore.warningThreshold { themeStore.warningThreshold = max(int - 5, 10) }
        }
        .onChange(of: marginSlider) { _, new in
            let int = Int(new)
            if settingsStore.pacingMargin != int { settingsStore.pacingMargin = int }
        }
        .onChange(of: themeStore.warningThreshold) { _, new in
            let d = Double(new); if warningSlider != d { warningSlider = d }
        }
        .onChange(of: themeStore.criticalThreshold) { _, new in
            let d = Double(new); if criticalSlider != d { criticalSlider = d }
        }
        .onChange(of: settingsStore.pacingMargin) { _, new in
            let d = Double(new); if marginSlider != d { marginSlider = d }
        }
    }

    // MARK: - Workweek pacing card

    private var workweekCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 6) {
                        cardLabel(String(localized: "settings.pacing.workweek"))
                        Button {
                            showWorkweekPopover.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showWorkweekPopover, arrowEdge: .bottom) {
                            workweekInfoPopover
                                .background(DS.Palette.bgElevated)
                                .preferredColorScheme(.dark)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $settingsStore.pacingWorkweekEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if settingsStore.pacingWorkweekEnabled {
                    HStack(spacing: 6) {
                        ForEach(orderedWeekdays, id: \.day) { item in
                            dayChip(day: item.day, symbol: item.symbol)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(String(localized: "settings.pacing.workweek.hours"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Toggle("", isOn: $settingsStore.pacingHoursEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    if settingsStore.pacingHoursEnabled {
                        HStack(spacing: 10) {
                            Text(String(format: "%02d:00", settingsStore.pacingStartHour))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.accentSettings)
                                .frame(width: 44, alignment: .leading)
                            HourRangeSlider(
                                startHour: $settingsStore.pacingStartHour,
                                endHour: $settingsStore.pacingEndHour
                            )
                            .frame(maxWidth: .infinity)
                            Text(String(format: "%02d:00", settingsStore.pacingEndHour))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.accentSettings)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Text(String(localized: "settings.pacing.workweek.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Workweek pacing popover

    private var workweekInfoPopover: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.brandPrimary)
                Text(String(localized: "settings.workweek.popover.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
            }

            Text(String(localized: "settings.workweek.popover.intro"))
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider().opacity(0.18)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                signalRow(
                    index: 1,
                    title: String(localized: "settings.workweek.popover.point1.title"),
                    desc: String(localized: "settings.workweek.popover.point1.desc"),
                    tint: DS.Palette.brandPrimary
                )
                signalRow(
                    index: 2,
                    title: String(localized: "settings.workweek.popover.point2.title"),
                    desc: String(localized: "settings.workweek.popover.point2.desc"),
                    tint: Color(hex: themeStore.current.gaugeWarning)
                )
                signalRow(
                    index: 3,
                    title: String(localized: "settings.workweek.popover.point3.title"),
                    desc: String(localized: "settings.workweek.popover.point3.desc"),
                    tint: DS.Palette.semanticInfo
                )
            }

            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.top, 1)
                Text(String(localized: "settings.workweek.popover.footer"))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(DS.Spacing.lg)
        .frame(width: 360)
    }

    // MARK: - Workweek pacing day picker

    /// Weekday chips ordered by the user's locale first weekday (Mon-first in
    /// FR, Sun-first in US). `day` is the Gregorian weekday number (1=Sun...7=Sat).
    private var orderedWeekdays: [(day: Int, symbol: String)] {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols // index 0 = Sunday
        let first = cal.firstWeekday // 1...7
        return (0..<7).map { offset in
            let day = ((first - 1 + offset) % 7) + 1
            return (day, symbols[day - 1])
        }
    }

    private func dayChip(day: Int, symbol: String) -> some View {
        let selected = settingsStore.pacingActiveDays.contains(day)
        return Button {
            toggleActiveDay(day)
        } label: {
            Text(symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(selected ? DS.Palette.brandPrimary.opacity(0.22) : Color.white.opacity(0.06))
                )
                .overlay(
                    Circle().stroke(selected ? DS.Palette.brandPrimary.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .foregroundStyle(selected ? DS.Palette.brandPrimary : Color.white.opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    /// Toggles a day on/off, keeping at least one active day so the pacing
    /// denominator can never hit zero.
    private func toggleActiveDay(_ day: Int) {
        var days = settingsStore.pacingActiveDays
        if days.contains(day) {
            guard days.count > 1 else { return }
            days.remove(day)
        } else {
            days.insert(day)
        }
        settingsStore.pacingActiveDays = days
    }

    // MARK: - Smart Color profile picker

    private var smartColorProfilePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardLabel(String(localized: "settings.smartColor.profile.label"))
            HStack(spacing: 8) {
                ForEach(SmartColorProfile.allCases, id: \.self) { profile in
                    profileCard(profile)
                }
            }
        }
    }

    private func profileCard(_ profile: SmartColorProfile) -> some View {
        let isActive = settingsStore.smartColorProfile == profile
        let accent = DS.Palette.brandPrimary
        return Button {
            withAnimation(DS.Motion.springSnap) {
                settingsStore.smartColorProfile = profile
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: profileIcon(profile))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? accent : DS.Palette.textTertiary)
                        .frame(width: 16)
                    Text(profileDisplayLabel(profile))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(profileHint(for: profile))
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? accent.opacity(0.14) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isActive ? accent.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func profileIcon(_ profile: SmartColorProfile) -> String {
        switch profile {
        case .patient:  return "tortoise.fill"
        case .balanced: return "equal.circle.fill"
        case .vigilant: return "eye.fill"
        }
    }

    private func profileDisplayLabel(_ profile: SmartColorProfile) -> String {
        switch profile {
        case .patient:  return String(localized: "settings.smartColor.profile.patient")
        case .balanced: return String(localized: "settings.smartColor.profile.balanced")
        case .vigilant: return String(localized: "settings.smartColor.profile.vigilant")
        }
    }

    private func profileHint(for profile: SmartColorProfile) -> String {
        switch profile {
        case .patient:  return String(localized: "settings.smartColor.profile.patient.hint")
        case .balanced: return String(localized: "settings.smartColor.profile.balanced.hint")
        case .vigilant: return String(localized: "settings.smartColor.profile.vigilant.hint")
        }
    }

    // MARK: - Smart Color popover

    private var smartColorInfoPopover: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.brandPrimary)
                Text(String(localized: "settings.smartcolor.popover.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
            }

            Text(String(localized: "settings.smartcolor.popover.intro"))
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider().opacity(0.18)

            VStack(spacing: DS.Spacing.sm) {
                smartColorExample(
                    glyph: "leaf.fill",
                    pct: 95,
                    resetText: "2 min",
                    zoneLabel: String(localized: "settings.smartcolor.popover.example1.label"),
                    color: Color(hex: themeStore.current.gaugeNormal),
                    explanation: String(localized: "settings.smartcolor.popover.example1")
                )
                smartColorExample(
                    glyph: "flame.fill",
                    pct: 50,
                    resetText: "5 h",
                    zoneLabel: String(localized: "settings.smartcolor.popover.example2.label"),
                    color: Color(hex: themeStore.current.gaugeCritical),
                    explanation: String(localized: "settings.smartcolor.popover.example2")
                )
            }

            Divider().opacity(0.18)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(String(localized: "settings.smartcolor.popover.signals.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.bottom, 2)

                signalRow(
                    index: 1,
                    title: String(localized: "settings.smartcolor.popover.signal.absolute.title"),
                    desc: String(localized: "settings.smartcolor.popover.signal.absolute.desc"),
                    tint: Color(hex: themeStore.current.gaugeCritical)
                )
                signalRow(
                    index: 2,
                    title: String(localized: "settings.smartcolor.popover.signal.projection.title"),
                    desc: String(localized: "settings.smartcolor.popover.signal.projection.desc"),
                    tint: Color(hex: themeStore.current.gaugeWarning)
                )
                signalRow(
                    index: 3,
                    title: String(localized: "settings.smartcolor.popover.signal.pacing.title"),
                    desc: String(localized: "settings.smartcolor.popover.signal.pacing.desc"),
                    tint: DS.Palette.brandPrimary
                )

                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    Image(systemName: "function")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.top, 1)
                    Text(String(localized: "settings.smartcolor.popover.combine"))
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)

                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.top, 1)
                    Text(String(localized: "settings.smartcolor.popover.profile"))
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(String(localized: "settings.smartcolor.popover.formula"))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .italic()
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Spacing.xxs)
        }
        .padding(DS.Spacing.lg)
        .frame(width: 400)
    }

    private func signalRow(index: Int, title: String, desc: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(tint.opacity(0.14))
                        .overlay(Circle().stroke(tint.opacity(0.45), lineWidth: 0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
        }
    }

    private func smartColorExample(
        glyph: String,
        pct: Int,
        resetText: String,
        zoneLabel: String,
        color: Color,
        explanation: String
    ) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.45), radius: 6)
                Text("\(pct)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(resetText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(zoneLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(color)
                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(color.opacity(0.28), lineWidth: 1)
                )
        )
    }

    // MARK: - Sliders + previews

    private func thresholdSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 60, alignment: .leading)
            TokenEaterSlider(value: value, in: range, step: 5, showsTicks: true)
            Text("\(Int(value.wrappedValue))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// Live 4-zone preview reflecting the current pacing margin.
    private var pacingZonesPreview: some View {
        let m = Int(marginSlider)
        let chipColors: [(PacingZone, String)] = [
            (.chill,   "< -\(m)%"),
            (.onTrack, "\u{00B1}\(m)%"),
            (.warning, "+\(m)..+\(m * 2)%"),
            (.hot,     "> +\(m * 2)%"),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(chipColors.enumerated()), id: \.offset) { _, entry in
                pacingZoneChip(zone: entry.0, range: entry.1)
            }
        }
    }

    private func pacingZoneChip(zone: PacingZone, range: String) -> some View {
        let color = themeStore.current.pacingColor(for: zone)
        let label = NSLocalizedString("pacing.zone.\(zone.rawValue.lowercased())", comment: "")
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(range)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(color.opacity(0.45), lineWidth: 0.6)
                )
        )
    }

    private func themePreviewGauge(pct: Double, label: String) -> some View {
        let color = themeStore.current.gaugeColor(for: pct, thresholds: themeStore.thresholds)
        return VStack(spacing: 4) {
            RingGauge(
                percentage: Int(pct),
                gradient: themeStore.current.gaugeGradient(for: pct, thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing),
                size: 40,
                glowColor: color,
                glowRadius: 3
            )
            .overlay {
                GlowText(
                    "\(Int(pct))%",
                    font: .system(size: 10, weight: .black, design: .rounded),
                    color: color,
                    glowRadius: 2
                )
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
