import Foundation

protocol ClaudeTokenRefreshing: Sendable {
    var isCLIInstalled: Bool { get }
    func refresh() async
}

/// Claude Code rotates its refresh token, so TokenBar never refreshes OAuth itself: doing so would
/// invalidate the CLI's stored login. Instead it briefly runs a non-inference CLI command, letting
/// the CLI refresh and persist its own credential, then rereads the Keychain.
struct ClaudeCLIRefresher: ClaudeTokenRefreshing {
    var timeoutSeconds: Double = 15

    var isCLIInstalled: Bool { Self.cliExecutable() != nil }

    /// Prefers a `claude` on PATH, then the Claude Code build bundled with the Claude desktop app,
    /// which shares the same Keychain login.
    static func cliExecutable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        if let installed = executable(named: "claude") { return installed }
        let bundles = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = (try? FileManager.default.contentsOfDirectory(at: bundles, includingPropertiesForKeys: nil)) ?? []
        let candidates = versions.flatMap { version in
            ((try? FileManager.default.contentsOfDirectory(at: version, includingPropertiesForKeys: nil)) ?? [])
                .map { $0.appendingPathComponent("claude.app/Contents/MacOS/claude") }
        }
        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
            .max { $0.path.compare($1.path, options: .numeric) == .orderedAscending }
    }

    func refresh() async {
        guard let executable = Self.cliExecutable() else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["auth", "status"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
