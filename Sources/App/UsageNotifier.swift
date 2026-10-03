import Foundation
import UserNotifications

/// Thin wrapper around the system notification center. Permission is requested only when the
/// person enables an alert rule, never at launch.
@MainActor
final class UsageNotifier: NSObject, UNUserNotificationCenterDelegate {
    private lazy var center: UNUserNotificationCenter = {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func deliver(_ alert: LimitAlert) {
        let percent = Int((alert.limit.usedFraction * 100).rounded())
        var body = "\(alert.limit.label) is at \(percent)% (alert at \(alert.threshold)%)."
        if let reset = alert.limit.resetsAt {
            body += " Resets \(reset.formatted(.relative(presentation: .named)))."
        }
        post(id: LimitAlertEvaluator.key(alert.provider, alert.limit, alert.threshold),
             title: "\(alert.provider.displayName) limit at \(percent)%", body: body)
    }

    func sendTest() {
        post(id: "test-\(UUID().uuidString)", title: "TokenBar notifications are on",
             body: "You'll be alerted when a limit crosses one of your thresholds.")
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // The panel can make TokenBar the active app, so present banners even while frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
