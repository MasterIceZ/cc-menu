# CC-Menu

A minimal macOS menu bar app that shows Claude AI quota usage as plain text.

## Goal

Display two values in the macOS menu bar, updated every 60 seconds:

```
✽ 42% 71%
```

- First % = current 5-hour session usage
- Second % = 7-day weekly usage

## Constraints

- Swift Package only — no `.xcodeproj`, no storyboards, no NIB files
- Target: macOS 13+
- No third-party dependencies — only Foundation, AppKit, Security frameworks
- Single executable target in `Package.swift` named `cc-menu`
- Swift language mode: v5

## Architecture

Single file: `Sources/cc-menu/cc_menu.swift`

1. **NSStatusItem** — shows text in the menu bar
2. **Keychain reader** — reads Claude Code's stored OAuth access token
3. **API poller** — calls the Anthropic OAuth usage endpoint
4. **Timer** — refreshes every 60 seconds
5. **NSMenu** — shown on click with reset times, New Chat link, and Quit

## Keychain

- Service name: `"Claude Code-credentials"`
- Use `SecItemCopyMatching` with `kSecClassGenericPassword` and `kSecMatchLimitOne`
- Data is a JSON blob: `{"claudeAiOauth": {"accessToken": "...", "refreshToken": "..."}}`
- Credentials are read once at launch and cached in memory to avoid repeated keychain prompts

## API

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access_token>
anthropic-beta: oauth-2025-04-20
```

Response structure:
```json
{
  "five_hour":  { "utilization": 20.0, "resets_at": "2026-05-22T10:50:00Z" },
  "seven_day":  { "utilization": 5.0,  "resets_at": "2026-05-24T03:00:00Z" }
}
```

On 401/403, attempt a token refresh via:
```
POST https://claude.ai/api/auth/oauth/refresh
{"refresh_token": "<token>"}
```

## Menu bar text format

```
✽ 20% 5%
```

- Round to nearest integer
- No internet: `⚠ --% --%`
- Token missing/expired: `Claude: no auth`
- Loading/error: `✽ --% --%`

## Menu (on click)

```
Session resets in 2h 15m
Weekly resets May 24, 2026 at 10:00 AM
———————————————————
New Chat                    ⌘N
———————————————————
Quit                        ⌘Q
```

## Error handling

- Network error (no internet): show `⚠ --% --%`
- Other errors: keep last known values, log to stderr
- 401/403: refresh token once, then show `Claude: no auth`

## Build & run

```bash
swift build
.build/debug/cc-menu
```

## Distribution (Homebrew cask)

Build script produces a universal `.app` bundle:

```bash
bash scripts/build-app.sh 1.0.0
```

This creates `cc-menu.app` (with `LSUIElement=YES` so no dock icon) and zips it to `cc-menu.zip`.

Upload `cc-menu.zip` to a GitHub Release, then reference in `homebrew-tap`:
- Repo: `MasterIceZ/homebrew-tap`
- Cask: `Casks/cc-menu.rb`

Install:
```bash
brew tap MasterIceZ/tap
brew install --cask cc-menu
```

## What NOT to build

- No preferences window
- No notifications
- No Sparkle / auto-update framework
- No LaunchAgent setup (user handles that via Login Items)
