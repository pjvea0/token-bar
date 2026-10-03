import Foundation
import XCTest
@testable import TokenBar

final class ClaudeAuthTests: XCTestCase {
    private let missingFile = URL(fileURLWithPath: "/nonexistent/.credentials.json")

    private static func credentialData(token: String, expiresAt: Int) -> Data {
        Data(#"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":\#(expiresAt)}}"#.utf8)
    }

    private static let past = 1_000_000_000_000
    private static let future = 4_000_000_000_000

    func testLoaderPrefersFreshestCredentialOverStaleFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Self.credentialData(token: "stale-file", expiresAt: Self.past).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let loader = ClaudeCredentialLoader { Self.credentialData(token: "fresh-keychain", expiresAt: Self.future) }

        XCTAssertEqual(loader.load(fileURL: file)?.accessToken, "fresh-keychain")
    }

    func testExpiredCredentialTriggersOneCLIRefreshThenFetches() async {
        let keychain = MutableData(Self.credentialData(token: "old", expiresAt: Self.past))
        let refresher = StubRefresher { keychain.value = Self.credentialData(token: "new", expiresAt: Self.future) }
        let fetched = MutableData(Data())
        var collector = ClaudeLimitCollector(credentialLoader: ClaudeCredentialLoader { keychain.value }, refresher: refresher)
        collector.fetch = { credential in
            fetched.value = Data(credential.accessToken.utf8)
            return (200, Data(#"{"five_hour":{"utilization":10}}"#.utf8))
        }

        let result = await collector.enrich(Self.emptyUsage, credentialsURL: missingFile)

        XCTAssertEqual(refresher.calls.value, 1)
        XCTAssertEqual(String(decoding: fetched.value, as: UTF8.self), "new")
        XCTAssertNil(result.status)
        XCTAssertEqual(result.limits.first?.usedFraction, 0.1)
    }

    func testUnrecoverableExpiryOffersCLILaunchWithoutLeakingToken() async {
        let refresher = StubRefresher {}
        var collector = ClaudeLimitCollector(credentialLoader: ClaudeCredentialLoader { Self.credentialData(token: "secret-old", expiresAt: Self.past) },
                                             refresher: refresher)
        collector.fetch = { _ in XCTFail("Expired token must not be sent"); return (500, Data()) }

        let result = await collector.enrich(Self.emptyUsage, credentialsURL: missingFile)

        XCTAssertEqual(refresher.calls.value, 1)
        XCTAssertEqual(result.action, .openCLI)
        XCTAssertFalse((result.status ?? "").contains("secret") || (result.help ?? "").contains("secret"))
    }

    func testUnauthorizedResponseRefreshesAndRetriesOnce() async {
        let keychain = MutableData(Self.credentialData(token: "revoked", expiresAt: Self.future))
        let refresher = StubRefresher { keychain.value = Self.credentialData(token: "renewed", expiresAt: Self.future + 1) }
        var collector = ClaudeLimitCollector(credentialLoader: ClaudeCredentialLoader { keychain.value }, refresher: refresher)
        collector.fetch = { credential in
            credential.accessToken == "renewed" ? (200, Data(#"{"seven_day":{"utilization":50}}"#.utf8)) : (401, Data())
        }

        let result = await collector.enrich(Self.emptyUsage, credentialsURL: missingFile)

        XCTAssertEqual(refresher.calls.value, 1)
        XCTAssertEqual(result.limits.map(\.label), ["Weekly (7-day)"])
    }

    func testMissingCLIExplainsDesktopOnlySetup() async {
        let refresher = StubRefresher(installed: false) {}
        let collector = ClaudeLimitCollector(credentialLoader: ClaudeCredentialLoader { nil }, refresher: refresher)

        let result = await collector.enrich(Self.emptyUsage, credentialsURL: missingFile)

        XCTAssertEqual(result.status, "Claude Code CLI not installed")
        XCTAssertEqual(refresher.calls.value, 0)
    }

    private static let emptyUsage = ProviderUsage(id: .claude, plan: "", limits: [], days: [], models: [],
                                                  historyScope: .allLocalHistory, totalPrompts: 0, totalSessions: 0,
                                                  activeDays: 0, updatedAt: .now, status: nil, help: nil)
}

private final class MutableData: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data
    init(_ value: Data) { stored = value }
    var value: Data {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    func increment() { lock.withLock { stored += 1 } }
}

private struct StubRefresher: ClaudeTokenRefreshing {
    var installed = true
    let calls = Counter()
    let onRefresh: @Sendable () -> Void

    init(installed: Bool = true, onRefresh: @escaping @Sendable () -> Void) {
        self.installed = installed
        self.onRefresh = onRefresh
    }

    var isCLIInstalled: Bool { installed }
    func refresh() async {
        calls.increment()
        onRefresh()
    }
}
