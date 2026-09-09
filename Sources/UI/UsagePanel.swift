import AppKit
import SwiftUI

struct UsagePanel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if store.usages.count > 1 { providerPicker }
            if let usage = store.current { providerContent(usage) } else { emptyState }
            Divider()
            HStack {
                Button("Launch Agent", systemImage: "terminal", action: store.launchCurrent)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain)
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                }.buttonStyle(.plain).disabled(store.isRefreshing).keyboardShortcut("r", modifiers: [])
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain)
            }
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
            if store.isRefreshing { ProgressView().controlSize(.small) }
        }
    }

    private var providerPicker: some View {
        Picker("Provider", selection: $store.selected) {
            ForEach(store.usages) { Text($0.id.displayName).tag($0.id) }
        }.pickerStyle(.segmented).labelsHidden()
    }

    @ViewBuilder private func providerContent(_ usage: ProviderUsage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let status = usage.status {
                    Label { VStack(alignment: .leading) { Text(status).font(.callout.bold()); Text(usage.help ?? "").font(.caption) } }
                    icon: { Image(systemName: "exclamationmark.triangle") }.foregroundStyle(.orange)
                }
                ForEach(usage.limits) { limit in LimitRow(limit: limit) }
                if usage.hasUsage {
                    SectionTitle("Tokens by day")
                    DayChart(days: usage.days)
                    SectionTitle("Tokens by model")
                    ForEach(usage.models) { model in ModelRow(model: model) }
                    Text("\(usage.totalPrompts.formatted()) prompts · \(usage.totalSessions.formatted()) sessions · \(usage.activeDays.formatted()) active days")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxHeight: 550)
    }

    private var emptyState: some View {
        ContentUnavailableView("No usage yet", systemImage: "sparkles", description: Text("Sign in to Claude Code or Codex and complete a session, then refresh."))
            .frame(height: 220)
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.secondary) }
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

private struct DayChart: View {
    let days: [DayUsage]
    var body: some View {
        let maximum = max(1, days.map(\.tokens).max() ?? 1)
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { day in
                VStack {
                    RoundedRectangle(cornerRadius: 4).fill(.purple.gradient)
                        .frame(height: max(3, 72 * Double(day.tokens) / Double(maximum)))
                        .help("\(day.tokens.formatted()) tokens · \(day.prompts) prompts · \(day.sessions) sessions")
                    Text(day.date, format: .dateTime.weekday(.narrow)).font(.caption2)
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: 95, alignment: .bottom)
    }
}

private struct ModelRow: View {
    let model: ModelUsage
    var body: some View {
        HStack { Text(model.name).lineLimit(1); Spacer(); Text(model.tokens.total.formatted(.number.notation(.compactName))).monospacedDigit() }
            .font(.callout).padding(.vertical, 3)
            .help("Input \(model.tokens.input.formatted()) · Output \(model.tokens.output.formatted()) · Cache read \(model.tokens.cacheRead.formatted()) · Cache write \(model.tokens.cacheWrite.formatted())")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
