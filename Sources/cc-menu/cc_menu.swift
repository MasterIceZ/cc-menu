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

    let sessionPct = (json["five_hour"] as? [String: Any])?["utilization"] as? Double ?? 0
    let weeklyPct = (json["seven_day"] as? [String: Any])?["utilization"] as? Double ?? 0

    return UsageData(
        sessionPercent: Int(sessionPct.rounded()),
        weeklyPercent: Int(weeklyPct.rounded())
    )
}

struct UsageData {
    let sessionPercent: Int
    let weeklyPercent: Int
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

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var cachedCreds: KeychainCredentials?
    private var lastDisplay: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setDisplay("✺ S:--% W:--%")

        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu

        cachedCreds = readKeychainCredentials()

        Task { await poll() }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
    }

    private func setDisplay(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.title = text
        }
    }

    private func poll() async {
        guard let creds = cachedCreds else {
            setDisplay("Claude: no auth")
            return
        }

        do {
            let usage = try await fetchUsage(creds: creds)
            let text = "✺ S:\(usage.sessionPercent)% W:\(usage.weeklyPercent)%"
            lastDisplay = text
            setDisplay(text)
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
            setDisplay("⚠ S:--% W:--%")
        } catch {
            fputs("cc-menu: \(error)\n", stderr)
            setDisplay(lastDisplay ?? "✺ S:--% W:--%")
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
