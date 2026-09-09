import AppKit
import SwiftUI

struct UsagePanel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if store.usages.count > 1 { providerPicker }
            if let usage = store.current { providerContent(usage) } else { emptyState }
            footer
        }
        .padding(18)
        .frame(width: 390)
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").font(.title).foregroundStyle(.purple)
            VStack(alignment: .leading) {
                Text(store.current?.id.displayName ?? "TokenBar").font(.headline)
                Text(store.current?.plan.nonEmpty ?? "AI usage at a glance").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: [])
                .help("Refresh usage")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack {
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .help("Settings")
                if let usage = store.current {
                    UsageInfoButton(usage: usage)
                }
                Spacer()
                if let updatedAt = store.current?.updatedAt {
                    Text("Updated \(updatedAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit TokenBar")
            }
        }
    }

    private var providerPicker: some View {
        Picker("Provider", selection: $store.selected) {
            ForEach(store.usages) { Text($0.id.displayName).tag($0.id) }
        }.pickerStyle(.segmented).labelsHidden()
    }

    @ViewBuilder private func providerContent(_ usage: ProviderUsage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let status = usage.status {
                    Label { VStack(alignment: .leading) { Text(status).font(.callout.bold()); Text(usage.help ?? "").font(.caption) } }
                    icon: { Image(systemName: "exclamationmark.triangle") }.foregroundStyle(.orange)
                }
                ForEach(usage.limits) { limit in LimitRow(limit: limit) }
                if usage.hasUsage {
                    SectionTitle("Tokens by day", scope: "Last 7 days")
                    DayRows(days: usage.days)
                    SectionTitle("Tokens by model", scope: usage.historyScope.title)
                    ModelRows(models: usage.models)
                }
            }
        }.frame(maxHeight: 550)
    }

    private var emptyState: some View {
        ContentUnavailableView("No usage yet", systemImage: "sparkles", description: Text("Sign in to Claude Code or Codex and complete a session, then refresh."))
            .frame(height: 220)
    }
}

private struct UsageInfoButton: View {
    let usage: ProviderUsage
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .help("About usage totals")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Local usage totals").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    infoRow("History window", usage.historyScope.title)
                    infoRow("Tokens", usage.totalTokens.formatted())
                    infoRow("Prompts", usage.totalPrompts.formatted())
                    infoRow("Sessions", usage.totalSessions.formatted())
                    infoRow("Active days", usage.activeDays.formatted())
                }
                Divider()
                Text("These totals come from local CLI transcripts. They are separate from the provider-reported session and weekly limit cycles shown above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300)
        }
        .accessibilityLabel("About usage totals")
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

private struct SectionTitle: View {
    let title: String
    let scope: String
    init(_ title: String, scope: String) {
        self.title = title
        self.scope = scope
    }
    var body: some View {
        HStack {
            Text(title.uppercased()).fontWeight(.bold)
            Spacer()
            Text(scope.uppercased())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LimitRow: View {
    let limit: RateLimit
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(limit.label); Spacer(); Text(limit.usedFraction, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
            ProgressView(value: limit.usedFraction).tint(limit.usedFraction > 0.8 ? .orange : .purple)
            if let reset = limit.resetsAt { Text("Resets \(reset, style: .relative)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct DayRows: View {
    let days: [DayUsage]
    var body: some View {
        let maximum = max(1, days.map(\.tokens).max() ?? 1)
        VStack(spacing: 5) {
            ForEach(days) { day in
                UsageMeterRow(label: dayLabel(day.date), value: day.tokens,
                              fraction: Double(day.tokens) / Double(maximum))
                    .help("\(day.tokens.formatted()) tokens · \(day.prompts) prompts · \(day.sessions) sessions")
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

private struct ModelRows: View {
    let models: [ModelUsage]
    var body: some View {
        let maximum = max(1, models.map(\.tokens.total).max() ?? 1)
        VStack(spacing: 5) {
            ForEach(models) { model in
                UsageMeterRow(label: model.name, value: model.tokens.total,
                              fraction: Double(model.tokens.total) / Double(maximum))
                    .help("Input \(model.tokens.input.formatted()) · Output \(model.tokens.output.formatted()) · Cache read \(model.tokens.cacheRead.formatted()) · Cache write \(model.tokens.cacheWrite.formatted())")
            }
        }
    }
}

private struct UsageMeterRow: View {
    let label: String
    let value: Int
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.purple.opacity(0.16))
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                HStack(spacing: 8) {
                    Text(label).lineLimit(1)
                    Spacer()
                    Text(value.formatted(.number.notation(.compactName))).monospacedDigit()
                }
                .padding(.horizontal, 7)
            }
        }
        .frame(height: 27)
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value.formatted()) tokens")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
