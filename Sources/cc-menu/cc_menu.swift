import AppKit
import Foundation
import Security

// MARK: - Keychain

struct KeychainCredentials {
    let accessToken: String
    let refreshToken: String?
}

func readKeychainCredentials() -> KeychainCredentials? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let accessToken = oauth["accessToken"] as? String
    else { return nil }

    return KeychainCredentials(
        accessToken: accessToken,
        refreshToken: oauth["refreshToken"] as? String
    )
}

// MARK: - API

enum ClaudeError: Error {
    case unauthorized
    case badStatus(Int)
    case parseFailure
}

private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
private let refreshURL = URL(string: "https://claude.ai/api/auth/oauth/refresh")!

private let isoParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

struct UsageData {
    let sessionPercent: Int
    let weeklyPercent: Int
    let sessionResetsAt: Date?
    let weeklyResetsAt: Date?
}

func getUsage(token: String) async throws -> UsageData {
    var req = URLRequest(url: usageURL)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    let (data, response) = try await URLSession.shared.data(for: req)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

    if statusCode == 401 || statusCode == 403 { throw ClaudeError.unauthorized }
    guard statusCode == 200 else { throw ClaudeError.badStatus(statusCode) }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw ClaudeError.parseFailure }

    let fiveHour = json["five_hour"] as? [String: Any]
    let sevenDay = json["seven_day"] as? [String: Any]

    let sessionPct = fiveHour?["utilization"] as? Double ?? 0
    let weeklyPct = sevenDay?["utilization"] as? Double ?? 0

    let sessionResetsAt = (fiveHour?["resets_at"] as? String).flatMap { isoParser.date(from: $0) }
    let weeklyResetsAt = (sevenDay?["resets_at"] as? String).flatMap { isoParser.date(from: $0) }

    return UsageData(
        sessionPercent: Int(sessionPct.rounded()),
        weeklyPercent: Int(weeklyPct.rounded()),
        sessionResetsAt: sessionResetsAt,
        weeklyResetsAt: weeklyResetsAt
    )
}

func doRefreshToken(_ refreshToken: String) async throws -> String {
    var req = URLRequest(url: refreshURL)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

    let (data, response) = try await URLSession.shared.data(for: req)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw ClaudeError.unauthorized
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let newToken = json["access_token"] as? String
    else { throw ClaudeError.unauthorized }

    return newToken
}

// MARK: - Formatters

private func formatRelative(_ date: Date) -> String {
    let secs = date.timeIntervalSinceNow
    guard secs > 0 else { return "now" }
    let h = Int(secs) / 3600
    let m = (Int(secs) % 3600) / 60
    if h > 0 { return "in \(h)h \(m)m" }
    return "in \(m)m"
}

private let absoluteFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var cachedCreds: KeychainCredentials?
    private var lastDisplay: String?

    private var sessionResetItem = NSMenuItem(title: "Session resets: —", action: nil, keyEquivalent: "")
    private var weeklyResetItem  = NSMenuItem(title: "Weekly resets: —",  action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setDisplay("✺ --% --%")

        sessionResetItem.isEnabled = false
        weeklyResetItem.isEnabled  = false

        let menu = NSMenu()
        menu.addItem(sessionResetItem)
        menu.addItem(weeklyResetItem)
        menu.addItem(.separator())
        let newChat = NSMenuItem(title: "New Chat", action: #selector(openNewChat), keyEquivalent: "n")
        newChat.target = self
        menu.addItem(newChat)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        cachedCreds = readKeychainCredentials()

        Task { await poll() }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
    }

    @objc private func openNewChat() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/new")!)
    }

    private func setDisplay(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.title = text
        }
    }

    private func updateMenuResets(session: Date?, weekly: Date?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let d = session {
                self.sessionResetItem.title = "Session resets \(formatRelative(d))"
            } else {
                self.sessionResetItem.title = "Session resets: —"
            }
            if let d = weekly {
                self.weeklyResetItem.title = "Weekly resets \(absoluteFormatter.string(from: d))"
            } else {
                self.weeklyResetItem.title = "Weekly resets: —"
            }
        }
    }

    private func poll() async {
        guard let creds = cachedCreds else {
            setDisplay("Claude: no auth")
            return
        }

        do {
            let usage = try await fetchUsage(creds: creds)
            let text = "✺ \(usage.sessionPercent)% \(usage.weeklyPercent)%"
            lastDisplay = text
            setDisplay(text)
            updateMenuResets(session: usage.sessionResetsAt, weekly: usage.weeklyResetsAt)
        } catch ClaudeError.unauthorized {
            cachedCreds = readKeychainCredentials()
            setDisplay("Claude: no auth")
        } catch let urlErr as URLError
            where urlErr.code == .notConnectedToInternet
               || urlErr.code == .networkConnectionLost
               || urlErr.code == .cannotFindHost
               || urlErr.code == .cannotConnectToHost
               || urlErr.code == .timedOut
        {
            setDisplay("⚠ --% --%")
        } catch {
            fputs("cc-menu: \(error)\n", stderr)
            setDisplay(lastDisplay ?? "✺ --% --%")
        }
    }

    private func fetchUsage(creds: KeychainCredentials) async throws -> UsageData {
        do {
            return try await getUsage(token: creds.accessToken)
        } catch ClaudeError.unauthorized {
            guard let rt = creds.refreshToken else { throw ClaudeError.unauthorized }
            let newToken = try await doRefreshToken(rt)
            cachedCreds = KeychainCredentials(accessToken: newToken, refreshToken: rt)
            return try await getUsage(token: newToken)
        }
    }
}

// MARK: - Entry Point

@main
struct CCMenu {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
