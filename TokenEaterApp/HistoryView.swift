import SwiftUI
import Charts

/// History space -> tokens-over-time browser sourced from `~/.claude/projects/**/*.jsonl`.
/// Mirrors the Monitoring layout (header + cards) but pivots around a stacked
/// bar chart by model with model-family filter chips. Performance-sensitive:
/// the underlying service caches per-file aggregates so repeat opens stay fast.
struct HistoryView: View {
    @StateObject private var store = HistoryStore()
    @State private var hoveredBucket: HistoryBucket?
    @State private var chartReveal: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header
                heroCard
                toolbar
                chartCard
                footerChips
            }
            .padding(DS.Spacing.md)
        }
        .onAppear {
            // Cache hit makes this a no-op when we already loaded recently.
            if !store.hasLoadedOnce {
                store.reload()
            }
        }
        .onChange(of: store.filter) { _, _ in
            triggerChartReveal()
        }
        .onChange(of: store.buckets.count) { _, _ in
            triggerChartReveal()
        }
    }

    /// Drives the per-bar staggered fade-in. Resets `chartReveal` to 0 then
    /// ramps it back to 1 with an easeOut curve. `barOpacity` then samples
    /// progress relative to its own index so bars appear left-to-right.
    /// Reduce-motion users get a single global crossfade with no stagger.
    private func triggerChartReveal() {
        if reduceMotion {
            chartReveal = 0
            withAnimation(.easeInOut(duration: 0.25)) {
                chartReveal = 1
            }
            return
        }
        chartReveal = 0
        withAnimation(.easeOut(duration: 0.6)) {
            chartReveal = 1
        }
    }

    /// Computes the opacity of bar at `index` out of `count`. The animation
    /// budget is split so each bar gets a 50% window to fade in, sliced
    /// progressively along the timeline. Result: leftmost bar starts at
    /// progress 0 and finishes at 0.5, rightmost finishes at 1.0.
    private func barOpacity(at index: Int, of count: Int) -> Double {
        guard count > 1 else { return chartReveal }
        let stagger = Double(index) / Double(count - 1) * 0.5
        return min(max((chartReveal - stagger) * 2.0, 0), 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                Text(String(localized: "history.title"))
                    .font(DS.Typography.title1)
                    .foregroundStyle(DS.Palette.textPrimary)
            }
            Spacer()
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }
            Text(String(format: String(localized: "history.sessionsCount"), store.summary.sessionsCount))
                .font(DS.Typography.label)
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        let total = store.summary.totalActive
        let cached = store.summary.totalCached
        let cacheHit = store.summary.cacheHitRate
        let delta = store.summary.deltaPercent

        return HStack(alignment: .center, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTokens(total))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .monospacedDigit()
                Text(String(localized: "history.hero.label"))
                    .font(DS.Typography.micro)
                    .tracking(0.8)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                breakdownLine(label: "history.hero.active", value: total)
                breakdownLine(label: "history.hero.cached", value: cached)
                breakdownLine(label: "history.hero.cacheHit", percent: cacheHit)
            }
            .font(DS.Typography.label)

            if let delta {
                deltaBadge(delta)
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(radius: DS.Radius.card)
    }

    private func deltaBadge(_ percent: Double) -> some View {
        let positive = percent >= 0
        let symbol = positive ? "arrow.up.right" : "arrow.down.right"
        let color = positive ? DS.Palette.accentStats : DS.Palette.accentHistory
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(String(format: "%@%.0f%% %@", positive ? "+" : "", percent, String(localized: "history.hero.deltaSuffix")))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(color.opacity(0.16))
                .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.6))
        )
    }

    private func breakdownLine(label: String.LocalizationValue, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(formatTokens(value))
                .foregroundStyle(DS.Palette.textPrimary)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(String(localized: label))
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    private func breakdownLine(label: String.LocalizationValue, percent: Double) -> some View {
        HStack(spacing: 6) {
            Text(formatPercent(percent * 100))
                .foregroundStyle(DS.Palette.textPrimary)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(String(localized: label))
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    /// Avoid the "100%" rounding artefact when the actual rate is e.g. 99.6%.
    /// We show one decimal whenever the value is in the 99-100 range; below 99
    /// the integer reading is honest enough.
    private func formatPercent(_ value: Double) -> String {
        if value >= 99 && value < 100 {
            return String(format: "%.1f%%", value)
        }
        return String(format: "%.0f%%", value)
    }

    // MARK: - Toolbar (range + filter chips)

    private var toolbar: some View {
        HStack(spacing: DS.Spacing.md) {
            rangePicker
            divider
            filterChips
            Spacer()
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(HistoryRange.allCases, id: \.rawValue) { r in
                Button {
                    store.range = r
                } label: {
                    Text(String(localized: String.LocalizationValue(r.labelKey)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(r == store.range ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(rangeBackground(active: r == store.range))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Palette.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func rangeBackground(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(DS.Palette.glassFillHi)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(DS.Palette.glassBorder, lineWidth: 1)
                )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Palette.glassBorderLo)
            .frame(width: 1, height: 18)
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            filterChip(filter: .all,
                       label: String(localized: "history.filter.all"),
                       total: store.summary.totalActive,
                       color: DS.Palette.accentHistory,
                       isPresent: true)
            ForEach(ModelFamily.allCases, id: \.self) { family in
                filterChip(
                    filter: .family(family),
                    label: family.displayName,
                    total: store.familyTotals[family] ?? 0,
                    color: chipColor(for: family),
                    isPresent: store.activeFamilies.contains(family)
                )
            }
        }
    }

    private func filterChip(
        filter: HistoryFilter,
        label: String,
        total: Int,
        color: Color,
        isPresent: Bool
    ) -> some View {
        let isActive = store.filter == filter
        return Button {
            guard isPresent else { return }
            store.setFilter(filter)
        } label: {
            HStack(spacing: 6) {
                if filter.isAll == false {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Text(formatTokens(total))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isPresent ? DS.Palette.textPrimary : DS.Palette.textTertiary.opacity(0.5))
            }
            .foregroundStyle(isActive ? DS.Palette.textPrimary : DS.Palette.textSecondary)
            .opacity(isPresent ? 1.0 : 0.4)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? DS.Palette.glassFillHi : DS.Palette.glassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isActive ? DS.Palette.glassBorder : DS.Palette.glassBorderLo, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPresent)
    }

    // MARK: - Chart

    private var chartCard: some View {
        ZStack(alignment: .topTrailing) {
            chart
                .frame(height: 240)
            if chartReveal < 1 {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.Palette.accentHistory)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(DS.Motion.springSnap, value: chartReveal < 1)
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity)
        .dsGlass(radius: DS.Radius.card)
    }

    @ViewBuilder
    private var chart: some View {
        if store.buckets.isEmpty && !store.isLoading {
            emptyState
        } else {
            chartContent
        }
    }

    private var chartContent: some View {
        let visibleKinds = ModelKind.stackOrder.filter { kind in
            !filteredOut(kind) && totalsByKind[kind] != nil
        }
        let bucketsArray = filteredBuckets
        let count = bucketsArray.count
        let filteredTotal = bucketsArray.reduce(0) { $0 + $1.totalActive }
        let domain = chartDomain

        return ZStack {
            Chart {
                ForEach(Array(bucketsArray.enumerated()), id: \.element.id) { index, bucket in
                    ForEach(visibleKinds, id: \.self) { kind in
                        if let value = bucket.tokensByModel[kind], value > 0 {
                            BarMark(
                                x: .value("date", bucket.date, unit: store.range.isHourly ? .hour : .day),
                                y: .value("tokens", value)
                            )
                            .foregroundStyle(by: .value("Model", kind.displayName))
                            .cornerRadius(3)
                            .opacity(barOpacity(at: index, of: count))
                        }
                    }
                }

                // Vertical guideline through the hovered bucket. Spans the
                // full chart so the alignment stays obvious from any bar
                // height. The tooltip itself is anchored elsewhere so it
                // can sit near the bar instead of pinned to the chart top.
                if let bucket = hoveredBucket {
                    RuleMark(x: .value("date", bucket.date, unit: store.range.isHourly ? .hour : .day))
                        .foregroundStyle(DS.Palette.textPrimary.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    // Invisible anchor for the tooltip. We blend the bar's
                    // own peak with a floor at 60% of the chart's max value
                    // so short bars don't drag the tooltip down to the
                    // baseline. Tall bars stay glued to their peak.
                    PointMark(
                        x: .value("date", bucket.date, unit: store.range.isHourly ? .hour : .day),
                        y: .value("tokens", tooltipAnchorY(for: bucket, in: bucketsArray))
                    )
                    .opacity(0)
                    .annotation(
                        position: .top,
                        spacing: 10,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        tooltipCard(for: bucket, visibleKinds: visibleKinds)
                    }
                }
            }
            .chartXScale(domain: domain.start...domain.end)
            .animation(DS.Motion.springLiquid, value: store.filter)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                handleChartHover(at: location, proxy: proxy, geo: geo, in: bucketsArray)
                            case .ended:
                                clearHover()
                            }
                        }
                }
            }

            if filteredTotal == 0 {
                filterEmptyOverlay
            }
        }
        .chartForegroundStyleScale(domain: visibleKinds.map { $0.displayName },
                                   range: visibleKinds.map { gradient(for: $0) })
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(formatTokens(intValue))
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
                            .monospacedDigit()
                    }
                }
                AxisGridLine()
                    .foregroundStyle(DS.Palette.glassBorderLo)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                AxisValueLabel(format: store.range.isHourly ? .dateTime.hour() : .dateTime.month(.abbreviated).day(),
                               centered: true)
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
            }
        }
        .chartLegend(position: .top, alignment: .trailing, spacing: 12)
        .onChange(of: store.filter) { _, _ in clearHover() }
        .onChange(of: store.range)  { _, _ in clearHover() }
    }

    // MARK: - Hover tooltip

    /// Picks the bucket whose interval contains the cursor's X position. Uses
    /// `proxy.value(atX:)` to map screen-space to chart-space, then matches
    /// against `[bucket.date, bucket.date + bucketSeconds)`. Interval-based
    /// matching is precise regardless of bar height - "closest center" was
    /// inaccurate because `bucket.date` is the start of the interval, not its
    /// center. Falls back to the nearest bucket if no interval matches (cursor
    /// outside any data range, e.g. between buckets due to gaps).
    private func handleChartHover(
        at location: CGPoint,
        proxy: ChartProxy,
        geo: GeometryProxy,
        in buckets: [HistoryBucket]
    ) {
        guard !buckets.isEmpty,
              let plotFrameAnchor = proxy.plotFrame else {
            clearHover()
            return
        }
        let plotRect = geo[plotFrameAnchor]
        let xInPlot = location.x - plotRect.origin.x
        guard xInPlot >= 0, xInPlot <= plotRect.size.width,
              let cursorDate: Date = proxy.value(atX: xInPlot) else {
            clearHover()
            return
        }
        let bucketSeconds = store.range.bucketSeconds
        let containing = buckets.first { bucket in
            let start = bucket.date
            let end = start.addingTimeInterval(bucketSeconds)
            return cursorDate >= start && cursorDate < end
        }
        let resolved = containing ?? buckets.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(cursorDate)) < abs(rhs.date.timeIntervalSince(cursorDate))
        }
        guard let resolved else { return }
        if hoveredBucket?.id != resolved.id {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.18)) {
                hoveredBucket = resolved
            }
        }
    }

    /// Computes the Y anchor (in tokens) for the tooltip. Returns the bar's
    /// own peak when it's tall enough, otherwise lifts to 60% of the chart's
    /// max bar so short bars don't pull the tooltip to the baseline. Result:
    /// the tooltip sits in a comfortable upper-middle band regardless of which
    /// bar is hovered.
    private func tooltipAnchorY(for bucket: HistoryBucket, in buckets: [HistoryBucket]) -> Int {
        let max = buckets.map(\.totalActive).max() ?? 0
        let floor = Int(Double(max) * 0.6)
        return Swift.max(bucket.totalActive, floor)
    }

    private func clearHover() {
        guard hoveredBucket != nil else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.18)) {
            hoveredBucket = nil
        }
    }

    /// Floating tooltip rendered above the hovered bar. Carries:
    /// - the bucket date (formatted for the active resolution),
    /// - the total active tokens of the bucket as the headline number,
    /// - per-model breakdown limited to the visibleKinds (so filters stay honest),
    /// - a footer line with sessions count when present.
    @ViewBuilder
    private func tooltipCard(for bucket: HistoryBucket, visibleKinds: [ModelKind]) -> some View {
        let kinds = visibleKinds.filter { (bucket.tokensByModel[$0] ?? 0) > 0 }
        let total = kinds.reduce(0) { $0 + (bucket.tokensByModel[$1] ?? 0) }

        VStack(alignment: .leading, spacing: 8) {
            Text(formatTooltipDate(bucket.date))
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DS.Palette.textTertiary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatTokens(total))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .monospacedDigit()
                Text("history.tooltip.tokens")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            if !kinds.isEmpty {
                Rectangle()
                    .fill(DS.Palette.glassBorderLo)
                    .frame(height: 1)
                    .padding(.vertical, 1)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(kinds, id: \.self) { kind in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(gradient(for: kind))
                                .frame(width: 6, height: 6)
                                .shadow(color: gradient(for: kind).opacity(0.6), radius: 3)
                            Text(kind.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Palette.textSecondary)
                            Spacer(minLength: 16)
                            Text(formatTokens(bucket.tokensByModel[kind] ?? 0))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Palette.textPrimary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if bucket.sessionsCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(String(format: String(localized: "history.tooltip.sessions"), bucket.sessionsCount))
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .monospacedDigit()
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 170, maxWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Palette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Palette.glassBorder, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
        .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity),
                removal: .opacity
            )
        )
    }

    /// Tooltip date format -> "TUE, 14 APR" for daily, "14 APR · 14:00" for hourly.
    private func formatTooltipDate(_ date: Date) -> String {
        if store.range.isHourly {
            return date.formatted(.dateTime.day().month(.abbreviated).hour(.defaultDigits(amPM: .omitted)).minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Date range the chart should always span, even when only one bucket has
    /// data. Pinning the X scale prevents SwiftUI Charts from auto-fitting a
    /// single bar across the full chart width.
    /// End-of-domain rounds up to the next bucket boundary so today's bar
    /// (positioned at start-of-day / start-of-hour) fully fits within the
    /// drawing area instead of being clipped on the right edge.
    private var chartDomain: (start: Date, end: Date) {
        let now = Date()
        let cal = Calendar.current
        let end: Date
        if store.range.isHourly {
            // Round up to the next full hour so the current hour's bar fits.
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
            let startOfHour = cal.date(from: comps) ?? now
            end = cal.date(byAdding: .hour, value: 1, to: startOfHour) ?? now
        } else {
            // Round up to the start of tomorrow so today's bar fits.
            end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        }
        return (start: now.addingTimeInterval(-store.range.seconds), end: end)
    }

    /// Centered overlay shown when the active filter zeroes out every bucket
    /// in the range. Keeps the empty axes visible behind so the user
    /// understands the chart frame is intact.
    private var filterEmptyOverlay: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
            Text(filterEmptyMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Palette.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                )
        )
    }

    private var filterEmptyMessage: String {
        let rangeLabel = String(localized: String.LocalizationValue(store.range.labelKey))
        switch store.filter {
        case .all:
            return String(format: String(localized: "history.empty.filter.all"), rangeLabel)
        case .family(let family):
            return String(format: String(localized: "history.empty.filter.model"), family.displayName, rangeLabel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
            Text(String(localized: "history.empty.title"))
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textSecondary)
            Text(String(localized: "history.empty.subtitle"))
                .font(DS.Typography.label)
                .foregroundStyle(DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer chips

    private var footerChips: some View {
        HStack(spacing: 8) {
            chipCard(
                label: "history.chip.cacheHit",
                value: formatPercent(store.summary.cacheHitRate * 100),
                sub: String(format: String(localized: "history.chip.cacheHit.sub"), formatTokens(store.summary.totalCached))
            )
            chipCard(
                label: "history.chip.heaviest",
                value: heaviestLabel,
                sub: heaviestSub
            )
            chipCard(
                label: "history.chip.topProject",
                value: topProjectLabel,
                sub: topProjectSub
            )
            chipCard(
                label: "history.chip.topModel",
                value: topModelLabel,
                sub: topModelSub
            )
            chipCard(
                label: "history.chip.avgPerSession",
                value: formatTokens(store.summary.averagePerSession),
                sub: String(format: String(localized: "history.chip.avgPerSession.sub"), store.summary.sessionsCount)
            )
        }
    }

    private func chipCard(label: String.LocalizationValue, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: label))
                .font(DS.Typography.micro)
                .tracking(0.8)
                .foregroundStyle(DS.Palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Palette.textPrimary)
                .monospacedDigit()
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(radius: DS.Radius.card)
    }

    // MARK: - Computed presentation helpers

    private var filteredBuckets: [HistoryBucket] {
        switch store.filter {
        case .all:
            return store.buckets
        case .family(let family):
            return store.buckets.map { bucket in
                var b = bucket
                b.tokensByModel = bucket.tokensByModel.filter { $0.key.family == family }
                return b
            }
        }
    }

    private var totalsByKind: [ModelKind: Int] {
        var totals: [ModelKind: Int] = [:]
        for bucket in store.buckets {
            for (kind, tokens) in bucket.tokensByModel {
                totals[kind, default: 0] += tokens
            }
        }
        return totals
    }

    private func filteredOut(_ kind: ModelKind) -> Bool {
        switch store.filter {
        case .all: return false
        case .family(let family): return kind.family != family
        }
    }

    private var heaviestLabel: String {
        guard let bucket = store.summary.heaviestBucket else {
            return String(localized: "history.empty.dash")
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(store.range.isHourly ? "MMMd, h a" : "MMMd")
        return formatter.string(from: bucket.date)
    }

    private var heaviestSub: String {
        guard let bucket = store.summary.heaviestBucket else { return "—" }
        return String(format: String(localized: "history.chip.heaviest.sub"), formatTokens(bucket.totalActive))
    }

    private var topProjectLabel: String {
        guard let project = store.summary.topProject else {
            return String(localized: "history.empty.dash")
        }
        return URL(fileURLWithPath: project.path).lastPathComponent
    }

    private var topProjectSub: String {
        guard let project = store.summary.topProject else { return "—" }
        return String(format: String(localized: "history.chip.topProject.sub"), formatTokens(project.tokens))
    }

    private var topModelLabel: String {
        guard let model = store.summary.topModel else {
            return String(localized: "history.empty.dash")
        }
        return model.kind.displayName
    }

    private var topModelSub: String {
        guard let model = store.summary.topModel else { return "—" }
        let total = store.summary.totalActive
        let pct = total == 0 ? 0 : Int(Double(model.tokens) / Double(total) * 100)
        return String(format: String(localized: "history.chip.topModel.sub"), pct)
    }

    // MARK: - Formatting

    /// 1.2M / 540k / 96 etc. SI prefixes, no decimals below 10k.
    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            let m = Double(value) / 1_000_000
            return String(format: m >= 10 ? "%.0fM" : "%.1fM", m)
        }
        if value >= 1_000 {
            let k = Double(value) / 1_000
            return String(format: k >= 10 ? "%.0fk" : "%.1fk", k)
        }
        return "\(value)"
    }

    // MARK: - Color helpers

    /// Refined model palette - lower saturation than the brand pacing scale,
    /// better readability for back-to-back stacked segments.
    private func gradient(for kind: ModelKind) -> Color {
        switch kind {
        case .opus47: return Color(hex: "#E8A24A")
        case .opus46: return Color(hex: "#C2792B")
        case .sonnet: return Color(hex: "#5BC489")
        case .haiku:  return Color(hex: "#4FB7B0")
        case .other:  return Color(hex: "#9B8BD9")
        }
    }

    private func chipColor(for family: ModelFamily) -> Color {
        switch family {
        case .opus:   return Color(hex: "#E8A24A")
        case .sonnet: return Color(hex: "#5BC489")
        case .haiku:  return Color(hex: "#4FB7B0")
        case .other:  return Color(hex: "#9B8BD9")
        }
    }
}
