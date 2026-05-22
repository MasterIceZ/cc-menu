import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var cachedCreds: KeychainCredentials?
    private var lastDisplay: String?

    private var sessionResetItem = NSMenuItem(title: "Session resets: —", action: nil, keyEquivalent: "")
    private var weeklyResetItem  = NSMenuItem(title: "Weekly resets: —",  action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setDisplay("✽ --% --%")

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
            self.sessionResetItem.title = session.map { "Session resets \(formatRelative($0))" }
                ?? "Session resets: —"
            self.weeklyResetItem.title = weekly.map { "Weekly resets \(absoluteFormatter.string(from: $0))" }
                ?? "Weekly resets: —"
        }
    }

    private func poll() async {
        guard let creds = cachedCreds else {
            setDisplay("Claude: no auth")
            return
        }

        do {
            let usage = try await fetchUsage(creds: creds)
            let text = "✽ \(usage.sessionPercent)% \(usage.weeklyPercent)%"
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
            setDisplay(lastDisplay ?? "✽ --% --%")
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
