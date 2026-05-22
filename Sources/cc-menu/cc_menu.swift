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
        kSecAttrService as String: "Claude Code",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else { return nil }

    let dataItems: [Data]
    if let array = result as? [Data] {
        dataItems = array
    } else if let single = result as? Data {
        dataItems = [single]
    } else {
        return nil
    }

    for data in dataItems {
        // Try JSON blob {"access_token": "...", "refresh_token": "..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accessToken = json["access_token"] as? String
        {
            return KeychainCredentials(
                accessToken: accessToken,
                refreshToken: json["refresh_token"] as? String
            )
        }

        // Try plain JWT string
        if let token = String(data: data, encoding: .utf8), token.hasPrefix("ey") {
            return KeychainCredentials(accessToken: token, refreshToken: nil)
        }
    }

    return nil
}

// MARK: - API

enum ClaudeError: Error {
    case unauthorized
    case badStatus(Int)
    case parseFailure
}

func getOrgId(token: String) async throws -> String {
    var req = URLRequest(url: URL(string: "https://claude.ai/api/auth/session")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: req)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

    if statusCode == 401 { throw ClaudeError.unauthorized }
    guard statusCode == 200 else { throw ClaudeError.badStatus(statusCode) }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let memberships = json["memberships"] as? [[String: Any]],
        let org = memberships.first?["organization"] as? [String: Any],
        let orgId = org["id"] as? String
    else { throw ClaudeError.parseFailure }

    return orgId
}

struct UsageData {
    let sessionPercent: Int
    let weeklyPercent: Int
}

func getUsage(token: String, orgId: String) async throws -> UsageData {
    var req = URLRequest(
        url: URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: req)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

    if statusCode == 401 { throw ClaudeError.unauthorized }
    guard statusCode == 200 else { throw ClaudeError.badStatus(statusCode) }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let sessionPct = json["primary_usage_percent"] as? Double,
        let weeklyPct = json["weekly_usage_percent"] as? Double
    else { throw ClaudeError.parseFailure }

    return UsageData(
        sessionPercent: Int(sessionPct.rounded()),
        weeklyPercent: Int(weeklyPct.rounded())
    )
}

func doRefreshToken(_ refreshToken: String) async throws -> String {
    var req = URLRequest(url: URL(string: "https://claude.ai/api/auth/oauth/refresh")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

    let (data, response) = try await URLSession.shared.data(for: req)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw ClaudeError.unauthorized
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let newToken = json["access_token"] as? String
    else { throw ClaudeError.unauthorized }

    return newToken
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var cachedOrgId: String?
    private var lastDisplay: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setDisplay("S:--% W:--%")

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
        guard let creds = readKeychainCredentials() else {
            setDisplay("Claude: no auth")
            return
        }

        do {
            let usage = try await fetchUsage(creds: creds)
            let text = "S:\(usage.sessionPercent)% W:\(usage.weeklyPercent)%"
            lastDisplay = text
            setDisplay(text)
        } catch ClaudeError.unauthorized {
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
            setDisplay(lastDisplay ?? "S:--% W:--%")
        }
    }

    private func fetchUsage(creds: KeychainCredentials) async throws -> UsageData {
        do {
            return try await fetchUsageWithToken(creds.accessToken)
        } catch ClaudeError.unauthorized {
            guard let rt = creds.refreshToken else { throw ClaudeError.unauthorized }
            let newToken = try await doRefreshToken(rt)
            return try await fetchUsageWithToken(newToken)
        }
    }

    private func fetchUsageWithToken(_ token: String) async throws -> UsageData {
        if cachedOrgId == nil {
            cachedOrgId = try await getOrgId(token: token)
        }
        do {
            return try await getUsage(token: token, orgId: cachedOrgId!)
        } catch {
            cachedOrgId = nil
            throw error
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
