import Foundation

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
            let messages = [
                #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"TokenBar","version":"1"}}}"#,
                #"{"method":"initialized","params":{}}"#,
                #"{"id":2,"method":"account/read","params":{}}"#,
                #"{"id":3,"method":"account/rateLimits/read","params":{}}"#
            ].joined(separator: "\n") + "\n"
            input.fileHandleForWriting.write(Data(messages.utf8))
            input.fileHandleForWriting.closeFile()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            for line in data.split(separator: 0x0A) {
                guard let json = try? JSONDecoder().decode(JSONValue.self, from: line) else { continue }
                if json["id"]?.number == 2 {
                    result.plan = json["result"]?["account"]?["planType"]?.string ?? result.plan
                } else if json["id"]?.number == 3, let limits = json["result"]?["rateLimits"] {
                    result.plan = limits["planType"]?.string ?? result.plan
                    result.limits = [limits["primary"], limits["secondary"]].compactMap(limit)
                }
            }
            if result.limits.isEmpty {
                result.status = "Codex limits unavailable"
                result.help = "Run `codex login` to restore live limits."
            }
        } catch {
            result.status = "Codex limits unavailable"
            result.help = error.localizedDescription
        }
        return result
    }

    private func limit(_ value: JSONValue?) -> RateLimit? {
        guard let used = value?["usedPercent"]?.number else { return nil }
        let minutes = Int(value?["windowDurationMins"]?.number ?? 0)
        let label = minutes == 10_080 ? "Weekly (7-day)" : minutes > 0 ? "\(minutes / 60)h window" : "Limit"
        let reset = value?["resetsAt"]?.number.map { Date(timeIntervalSince1970: $0) }
        return RateLimit(label: label, usedFraction: min(1, used / 100), resetsAt: reset)
    }
}

struct ClaudeLimitCollector: Sendable {
    private let credentialLoader = ClaudeCredentialLoader()

    func enrich(_ usage: ProviderUsage, credentialsURL: URL) async -> ProviderUsage {
        var result = usage
        guard let credential = credentialLoader.load(fileURL: credentialsURL) else {
            result.status = "Waiting for auth"
            result.help = "Claude Code has no usable macOS Keychain or credential-file login. Run `claude auth login`, then verify `claude auth status` reports loggedIn: true."
            return result
        }
        if let expiry = credential.expiresAtMilliseconds, expiry <= Int(Date.now.timeIntervalSince1970 * 1_000) {
            result.status = "Sign-in expired"
            result.help = "Run `claude auth login` and verify `claude auth status` reports loggedIn: true. Local token statistics remain available."
            return result
        }
        result.plan = plan(credential.rateLimitTier, credential.subscriptionType)
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw URLError(.badServerResponse) }
            result.limits = [bucket(json["five_hour"], label: "Session (5-hour)"),
                             bucket(json["seven_day_oauth_apps"] ?? json["seven_day"], label: "Weekly (7-day)")].compactMap { $0 }
        } catch {
            result.status = "Claude limits unavailable"
            result.help = "\(error.localizedDescription) Local token statistics remain available."
        }
        return result
    }

    private func bucket(_ value: JSONValue?, label: String) -> RateLimit? {
        guard let raw = value?["utilization"]?.number else { return nil }
        let fraction = raw >= 1 ? raw / 100 : raw
        let reset = value?["resets_at"]?.string.flatMap(ISO8601DateFormatter().date)
        return RateLimit(label: label, usedFraction: min(1, fraction), resetsAt: reset)
    }

    private func plan(_ tier: String?, _ subscription: String?) -> String {
        if let tier, let range = tier.range(of: #"\d+x"#, options: .regularExpression) { return "Max \(tier[range])" }
        return subscription?.capitalized ?? ""
    }
}

private func executable(named name: String) -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin"]
    return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
}
