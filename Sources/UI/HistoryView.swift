import Charts
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
    case week, month, quarter, year, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        case .year: "1Y"
        case .custom: "Custom"
        }
    }
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .custom: nil
        }
    }
}

struct HistoryView: View {
    @ObservedObject var store: UsageStore
    @State private var provider: ProviderID = .claude
    @State private var range: HistoryRange = .month
    @State private var end = Calendar.current.startOfDay(for: .now)
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: .now))!
    @State private var history: UsageHistory?
    @State private var selectedDay: Date?

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }

    private var start: Date {
        if let days = range.days { return calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end }
        return min(customStart, end)
    }
    private var spanDays: Int { (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }

    private struct Query: Equatable {
        let provider: ProviderID, start: Date, end: Date, refreshed: [Date]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            if let history {
                if history.isEmpty {
                    ContentUnavailableView("No history in this range", systemImage: "clock.arrow.circlepath",
                                           description: Text(emptyDescription(history)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            summary(history)
                            limitChart(history)
                            tokenChart(history)
                            if let selectedDay, let day = history.days.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDay) }) {
                                DayDetail(day: day)
                            }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 560)
        .task(id: Query(provider: provider, start: start, end: end, refreshed: store.usages.map(\.updatedAt))) {
            history = await store.loadHistory(provider: provider, start: start, end: end)
        }
        .onAppear { provider = store.selected }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Provider", selection: $provider) {
                    ForEach(ProviderID.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            HStack(spacing: 8) {
                Button { shift(by: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Earlier")
                if range == .custom {
                    DatePicker("From", selection: $customStart, in: ...end, displayedComponents: .date).labelsHidden()
                    Text("–")
                    DatePicker("To", selection: endBinding, in: ...today, displayedComponents: .date).labelsHidden()
                } else {
                    Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
                        .monospacedDigit()
                }
                Button { shift(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(end >= today)
                    .help("Later")
                Spacer()
                if end < today {
                    Button("Today") { end = today }
                }
            }
        }
    }

    private var endBinding: Binding<Date> {
        Binding { end } set: { end = calendar.startOfDay(for: min($0, today)) }
    }

    private func shift(by direction: Int) {
        let span = spanDays
        let target = calendar.date(byAdding: .day, value: direction * span, to: end) ?? end
        let clamped = min(target, today)
        if range == .custom {
            customStart = calendar.date(byAdding: .day, value: -(span - 1), to: clamped) ?? clamped
        }
        end = clamped
        selectedDay = nil
    }

    private func emptyDescription(_ history: UsageHistory) -> String {
        if let earliest = history.earliestRecord {
            return "The earliest recorded \(provider.displayName) activity is \(earliest.formatted(date: .abbreviated, time: .omitted))."
        }
        return "TokenBar records history on every refresh. Daily totals are backfilled from local transcripts; limit percentages are recorded from now on."
    }

    // MARK: Sections

    private func summary(_ history: UsageHistory) -> some View {
        HStack(spacing: 28) {
            stat("Tokens", history.totalTokens.formatted(.number.notation(.compactName)))
            stat("Prompts", history.totalPrompts.formatted())
            stat("Active days", "\(history.activeDays) of \(history.days.count)")
            if let peak = history.samples.filter({ $0.window == .weekly }).map(\.usedFraction).max() {
                stat("Peak weekly", peak.formatted(.percent.precision(.fractionLength(0))))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
    }

    @ViewBuilder private func limitChart(_ history: UsageHistory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HistorySectionTitle("Limit usage", detail: "Provider-reported")
            if history.samples.isEmpty {
                Text("No limit samples were recorded in this range. TokenBar records limits while it is running.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(history.samples.enumerated()), id: \.offset) { _, sample in
                        LineMark(x: .value("Time", sample.date), y: .value("Used", sample.usedFraction * 100))
                            .foregroundStyle(by: .value("Limit", sample.label))
                            .interpolationMethod(.stepEnd)
                        PointMark(x: .value("Time", sample.date), y: .value("Used", sample.usedFraction * 100))
                            .foregroundStyle(by: .value("Limit", sample.label))
                            .symbolSize(18)
                    }
                    ForEach(thresholds, id: \.self) { threshold in
                        RuleMark(y: .value("Alert", threshold))
                            .foregroundStyle(.orange.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var chartDomain: ClosedRange<Date> {
        start...(calendar.date(byAdding: .day, value: 1, to: end) ?? end)
    }

    private var thresholds: [Int] {
        Array(Set(store.alertRules.filter { $0.provider == provider && $0.enabled }.flatMap(\.thresholds))).sorted()
    }

    private func tokenChart(_ history: UsageHistory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HistorySectionTitle("Tokens by day", detail: "Local transcripts · select a day")
            Chart {
                ForEach(history.days) { day in
                    ForEach(day.totals.models.sorted(by: { $0.key < $1.key }), id: \.key) { model, totals in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Tokens", totals.tokens.total))
                            .foregroundStyle(by: .value("Model", model))
                    }
                }
                if let selectedDay {
                    RuleMark(x: .value("Selected", selectedDay, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.3))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartXSelection(value: $selectedDay)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text((value.as(Int.self) ?? 0).formatted(.number.notation(.compactName))) }
                }
            }
            .frame(height: 220)
        }
    }
}

private struct HistorySectionTitle: View {
    let title: String
    let detail: String
    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
    var body: some View {
        HStack {
            Text(title.uppercased()).fontWeight(.bold)
            Spacer()
            Text(detail.uppercased())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct DayDetail: View {
    let day: HistoryDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HistorySectionTitle(day.date.formatted(date: .complete, time: .omitted),
                                detail: "\(day.totals.prompts) prompts · \(day.totals.sessions) sessions")
            if day.totals.models.isEmpty {
                Text("No local activity.").font(.callout).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    ForEach(["Model", "Input", "Output", "Cache read", "Cache write", "Total"], id: \.self) {
                        Text($0).foregroundStyle(.secondary)
                    }
                }
                ForEach(day.totals.models.sorted(by: { $0.value.tokens.total > $1.value.tokens.total }), id: \.key) { name, totals in
                    GridRow {
                        Text(name).lineLimit(1)
                        Text(totals.tokens.input.formatted())
                        Text(totals.tokens.output.formatted())
                        Text(totals.tokens.cacheRead.formatted())
                        Text(totals.tokens.cacheWrite.formatted())
                        Text(totals.tokens.total.formatted()).bold()
                    }
                    .monospacedDigit()
                }
            }
            .font(.callout)
        }
    }
}
