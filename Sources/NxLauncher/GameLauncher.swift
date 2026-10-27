import AppKit
import LauncherCore
import UserNotifications

/// Opens games and times them: every nxnative app (bundle ID org.nxnative.<title id>) that launches or quits while the launcher runs,
/// including those opened from Finder.
@MainActor
final class GameLauncher {
    private let began: (String) -> Void
    private let ended: (String) -> Void
    private var observers: [NSObjectProtocol] = []

    init(began: @escaping (String) -> Void, ended: @escaping (String) -> Void) {
        self.began = began; self.ended = ended
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let id = Self.titleID(n)
            MainActor.assumeIsolated { if let id { self?.began(id) } }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let id = Self.titleID(n)
            MainActor.assumeIsolated { if let id { self?.ended(id) } }
        })
    }

    nonisolated private static func titleID(_ n: Notification) -> String? {
        (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).flatMap { titleID(bundleID: $0.bundleIdentifier) }
    }

    nonisolated static func titleID(bundleID: String?) -> String? {
        guard let b = bundleID, b.hasPrefix(GameBundle.bundlePrefix) else { return nil }
        let id = String(b.dropFirst(GameBundle.bundlePrefix.count)).uppercased()
        return id.count == 16 && id.allSatisfy(\.isHexDigit) ? id : nil
    }

    /// Games already running when the launcher starts get a session from now.
    func adoptRunning() {
        for app in NSWorkspace.shared.runningApplications {
            if let id = Self.titleID(bundleID: app.bundleIdentifier) { began(id) }
        }
    }

    func open(_ game: GameBundle) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: game.url, configuration: config) { _, error in
            if let error {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "Could not open \(game.name)"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}

enum Notifier {
    /// A banner when a build ends; only from a bundled app (the notification center needs a bundle ID).
    static func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
