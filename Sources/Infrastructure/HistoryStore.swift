import Foundation

/// Persists normalized, credential-free usage history under Application Support.
/// Only numbers, dates, model names, and limit labels are written; never prompts, paths, or tokens.
/// Owned by the `UsageService` actor, which serializes every read and write.
final class HistoryStore {
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenBar/History", isDirectory: true)
    }

    /// A new sample is recorded when a limit moves by at least this fraction, its cycle changes,
    /// or `sampleInterval` passes. This keeps a 15-minute refresh cadence from bloating the log.
    static let minimumChange = 0.005
    static let sampleInterval: TimeInterval = 3_600

    private let directory: URL
    private let calendar: Calendar
    private var lastSamples: [String: LimitSample]?

    init(directory: URL = HistoryStore.defaultDirectory, calendar: Calendar = .current) {
        self.directory = directory
        self.calendar = calendar
    }

    private var limitsURL: URL { directory.appendingPathComponent("limits.jsonl") }
    private var dailyURL: URL { directory.appendingPathComponent("daily.json") }

    // MARK: Recording

    func recordDaily(provider: ProviderID, daily: [Date: DailyTotals]) {
        guard !daily.isEmpty else { return }
        var archive = loadDaily()
        var days = archive[provider.rawValue] ?? [:]
        var changed = false
        for (date, totals) in daily {
            let key = dayKey(date)
            let merged = days[key].map { $0.merged(with: totals) } ?? totals
            if days[key] != merged { days[key] = merged; changed = true }
        }
        guard changed else { return }
        archive[provider.rawValue] = days
        write(archive, to: dailyURL)
    }

    func recordLimits(provider: ProviderID, limits: [RateLimit], at date: Date = .now) {
        var last = loadLastSamples()
        var lines = Data()
        for limit in limits {
            let sample = LimitSample(date: date, provider: provider, label: limit.label, window: limit.window,
                                     usedFraction: limit.usedFraction, resetsAt: limit.resetsAt)
            let id = sampleID(provider, limit.label)
            if let previous = last[id], !isSignificant(sample, after: previous) { continue }
            guard let encoded = try? Self.encoder.encode(sample) else { continue }
            lines.append(encoded)
            lines.append(0x0A)
            last[id] = sample
        }
        lastSamples = last
        guard !lines.isEmpty, ensureDirectory() else { return }
        if let handle = try? FileHandle(forWritingTo: limitsURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: lines)
        } else {
            try? lines.write(to: limitsURL, options: .atomic)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        lastSamples = [:]
    }

    // MARK: Querying

    func history(provider: ProviderID, start: Date, end: Date) -> UsageHistory {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        let stored = loadDaily()[provider.rawValue] ?? [:]
        var days: [HistoryDay] = []
        var day = first
        while day <= last {
            days.append(HistoryDay(date: day, totals: stored[dayKey(day)] ?? DailyTotals()))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let allSamples = loadSamples().filter { $0.provider == provider }
        let samples = allSamples.filter { $0.date >= first && $0.date < rangeEnd }
        let earliestDay = stored.filter { $0.value.tokens > 0 }.keys.compactMap(date(fromKey:)).min()
        let earliest = [earliestDay, allSamples.first?.date].compactMap { $0 }.min()
        return UsageHistory(provider: provider, start: first, end: last, days: days, samples: samples, earliestRecord: earliest)
    }

    // MARK: Storage

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func loadDaily() -> [String: [String: DailyTotals]] {
        guard let data = try? Data(contentsOf: dailyURL) else { return [:] }
        return (try? Self.decoder.decode([String: [String: DailyTotals]].self, from: data)) ?? [:]
    }

    /// Malformed lines are skipped so one damaged write cannot hide the rest of the log.
    private func loadSamples() -> [LimitSample] {
        guard let data = try? Data(contentsOf: limitsURL) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(LimitSample.self, from: $0) }
            .sorted { $0.date < $1.date }
    }

    private func loadLastSamples() -> [String: LimitSample] {
        if let lastSamples { return lastSamples }
        var result: [String: LimitSample] = [:]
        for sample in loadSamples() { result[sampleID(sample.provider, sample.label)] = sample }
        lastSamples = result
        return result
    }

    private func isSignificant(_ sample: LimitSample, after previous: LimitSample) -> Bool {
        abs(sample.usedFraction - previous.usedFraction) >= Self.minimumChange
            || sample.date.timeIntervalSince(previous.date) >= Self.sampleInterval
            || abs((sample.resetsAt?.timeIntervalSince1970 ?? 0) - (previous.resetsAt?.timeIntervalSince1970 ?? 0)) >= 600
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard ensureDirectory(), let data = try? Self.encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func ensureDirectory() -> Bool {
        (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
    }

    private func sampleID(_ provider: ProviderID, _ label: String) -> String { "\(provider.rawValue)|\(label)" }

    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
    private func date(fromKey key: String) -> Date? { dayFormatter.date(from: key).map(calendar.startOfDay) }
}
