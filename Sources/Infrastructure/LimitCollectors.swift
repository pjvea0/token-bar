import Foundation
import Darwin

struct CodexLimitCollector: Sendable {
    func enrich(_ usage: ProviderUsage) -> ProviderUsage {
        var result = usage
        guard let executable = executable(named: "codex") else {
            result.status = "Codex limits unavailable"
            result.help = "Install Codex CLI and run `codex login`. Local token statistics remain available."
            return result
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "on-request", "app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            defer {
                input.fileHandleForWriting.closeFile()
                if process.isRunning { process.terminate() }
            }
            var reader = CodexRPCReader(handle: output.fileHandleForReading)
            try send(#"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"TokenBar","version":"1"}}}"#, to: input)
            guard try reader.response(id: 1, timeoutSeconds: 8) != nil else { throw CodexRPCError.timeout("initialize") }
            try send(#"{"method":"initialized","params":{}}"#, to: input)
            try send(#"{"id":2,"method":"account/read","params":{}}"#, to: input)
            let account = try reader.response(id: 2, timeoutSeconds: 4)
            try send(#"{"id":3,"method":"account/rateLimits/read","params":{}}"#, to: input)
            let rateResponse = try reader.response(id: 3, timeoutSeconds: 4)

            result.plan = account?["result"]?["account"]?["planType"]?.string ?? result.plan
            if let limits = rateResponse?["result"]?["rateLimits"] {
                result.plan = limits["planType"]?.string ?? result.plan
                result.limits = [limits["primary"], limits["secondary"]].compactMap(limit)
            }
            if result.limits.isEmpty {
                result.status = "Codex limits unavailable"
                result.help = rateResponse?["error"]?["message"]?.string ?? "Codex returned no live subscription limits."
            }
        } catch {
            result.status = "Codex limits unavailable"
            result.help = "\(error.localizedDescription) Your local token statistics remain available."
        }
        return result
    }

    private func send(_ message: String, to pipe: Pipe) throws {
        try pipe.fileHandleForWriting.write(contentsOf: Data((message + "\n").utf8))
    }

    private func limit(_ value: JSONValue?) -> RateLimit? {
        guard let used = value?["usedPercent"]?.number else { return nil }
        let minutes = Int(value?["windowDurationMins"]?.number ?? 0)
        let label = minutes == 10_080 ? "Weekly (7-day)" : minutes > 0 ? "\(minutes / 60)h window" : "Limit"
        let reset = value?["resetsAt"]?.number.map { Date(timeIntervalSince1970: $0) }
        return RateLimit(label: label, usedFraction: min(1, used / 100), resetsAt: reset)
    }
}

enum CodexRPCError: LocalizedError {
    case timeout(String)
    case streamClosed

    var errorDescription: String? {
        switch self {
        case let .timeout(method): "Codex timed out while handling \(method)."
        case .streamClosed: "Codex closed the app-server connection."
        }
    }
}

struct CodexRPCReader {
    let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    mutating func response(id: Int, timeoutSeconds: Int) throws -> JSONValue? {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date.now < deadline {
            while let line = nextLine() {
                guard let json = try? JSONDecoder().decode(JSONValue.self, from: line) else { continue }
                if json["id"]?.number == Double(id) { return json }
            }
            let remaining = max(1, Int(deadline.timeIntervalSinceNow * 1_000))
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let status = Darwin.poll(&descriptor, 1, Int32(remaining))
            if status == 0 { break }
            if status < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let byteCount = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if byteCount == 0 { throw CodexRPCError.streamClosed }
            if byteCount < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            buffer.append(contentsOf: bytes.prefix(byteCount))
        }
        return nil
    }

    private mutating func nextLine() -> Data? {
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = Data(buffer[..<newline])
        buffer.removeSubrange(...newline)
        return line
    }
}

struct ClaudeLimitCollector: Sendable {
    typealias Fetch = @Sendable (ClaudeCredential) async throws -> (status: Int, body: Data)

    var credentialLoader = ClaudeCredentialLoader()
    var refresher: any ClaudeTokenRefreshing = ClaudeCLIRefresher()
    var fetch: Fetch = ClaudeLimitCollector.requestUsage

    func enrich(_ usage: ProviderUsage, credentialsURL: URL) async -> ProviderUsage {
        var result = usage
        var credential = credentialLoader.load(fileURL: credentialsURL)
        var refreshed = false
        if let current = credential, current.isExpired(), refresher.isCLIInstalled {
            await refresher.refresh()
            refreshed = true
            credential = credentialLoader.load(fileURL: credentialsURL)
        }
        guard let credential else {
            if refresher.isCLIInstalled {
                result.status = "No Claude Code sign-in"
                result.help = "Run `claude auth login` once. TokenBar keeps the login fresh through the CLI afterwards."
                result.action = .openCLI
            } else {
                result.status = "Claude Code CLI not installed"
                result.help = "The Claude desktop app keeps its sign-in private. Install the Claude Code CLI and run `claude auth login` once to show live limits. Local token statistics remain available."
            }
            return result
        }
        guard !credential.isExpired() else { return expired(result) }
        result.plan = plan(credential.rateLimitTier, credential.subscriptionType)
        do {
            var response = try await fetch(credential)
            if response.status == 401, !refreshed, refresher.isCLIInstalled {
                await refresher.refresh()
                guard let renewed = credentialLoader.load(fileURL: credentialsURL), !renewed.isExpired(),
                      renewed.accessToken != credential.accessToken else { return expired(result) }
                response = try await fetch(renewed)
            }
            if response.status == 401 { return expired(result) }
            guard response.status == 200,
                  let json = try? JSONDecoder().decode(JSONValue.self, from: response.body) else { throw URLError(.badServerResponse) }
            result.limits = parseLimits(json)
            if result.limits.isEmpty {
                result.status = "Claude limits unavailable"
                result.help = "Anthropic returned no recognized subscription limits. Local token statistics remain available."
            }
        } catch {
            result.status = "Claude limits unavailable"
            result.help = "\(error.localizedDescription) Local token statistics remain available."
        }
        return result
    }

    private func expired(_ usage: ProviderUsage) -> ProviderUsage {
        var result = usage
        result.status = "Sign-in needs refreshing"
        result.help = "TokenBar could not refresh Claude Code's login automatically. Open Claude Code once so it can renew its token, then refresh. Local token statistics remain available."
        result.action = .openCLI
        return result
    }

    @Sendable static func requestUsage(_ credential: ClaudeCredential) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    func parseLimits(_ json: JSONValue) -> [RateLimit] {
        let session = json["five_hour"]?.object.map(JSONValue.object)
        let weekly = json["seven_day_oauth_apps"]?.object.map(JSONValue.object)
            ?? json["seven_day"]?.object.map(JSONValue.object)
        let scoped = json["limits"]?.array ?? []
        let rawValues = [session?["utilization"]?.number, weekly?["utilization"]?.number]
            + scoped.map { $0["percent"]?.number }
        let percentScale = rawValues.compactMap { $0 }.contains { $0 >= 1 }
        var limits = [bucket(session, label: "Session (5-hour)", percentScale: percentScale),
                      bucket(weekly, label: "Weekly (7-day)", percentScale: percentScale)].compactMap { $0 }
        var seenLabels = Set(limits.map(\.label))
        for entry in scoped {
            guard let model = entry["scope"]?["model"],
                  let rawName = model["display_name"]?.string ?? model["id"]?.string,
                  let raw = entry["percent"]?.number else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let kind = entry["kind"]?.string ?? ""
            let window = scopedWindow(kind)
            let label = window.isEmpty ? name : "\(name) \(window)"
            guard seenLabels.insert(label).inserted else { continue }
            limits.append(RateLimit(label: label, usedFraction: normalize(raw, percentScale: percentScale),
                                    resetsAt: resetDate(entry["resets_at"])))
        }
        return limits
    }

    private func bucket(_ value: JSONValue?, label: String, percentScale: Bool) -> RateLimit? {
        guard let raw = value?["utilization"]?.number else { return nil }
        return RateLimit(label: label, usedFraction: normalize(raw, percentScale: percentScale),
                         resetsAt: resetDate(value?["resets_at"]))
    }

    private func normalize(_ raw: Double, percentScale: Bool) -> Double {
        let fraction = (percentScale || raw > 1) ? raw / 100 : raw
        return min(1, max(0, fraction))
    }

    private func resetDate(_ value: JSONValue?) -> Date? {
        if let string = value?.string { return parseISO8601(string) }
        guard let raw = value?.number else { return nil }
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
    }

    private func scopedWindow(_ kind: String) -> String {
        let value = kind.lowercased()
        if value.contains("month") { return "Monthly" }
        if value.contains("week") || value.contains("day") { return "Weekly" }
        if value.contains("hour") || value.contains("session") { return "Session" }
        return ""
    }

    private func plan(_ tier: String?, _ subscription: String?) -> String {
        if let tier, let range = tier.range(of: #"\d+x"#, options: .regularExpression) { return "Max \(tier[range])" }
        return subscription?.capitalized ?? ""
    }
}

func executable(named name: String) -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin"]
    return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
}

/// Anthropic reports reset times with fractional seconds, which the default ISO 8601 formatter rejects.
func parseISO8601(_ string: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
}
