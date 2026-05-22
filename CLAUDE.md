# CC-Menu

A minimal macOS menu bar app that shows Claude AI quota usage as plain text.

## Goal

Display two values in the macOS menu bar, updated every 60 seconds:

```
S:42% W:71%
```

- **S** = current 5-hour session usage (%)
- **W** = weekly usage (%)

Nothing else. No popover, no window, no settings UI.

## Constraints

- Swift Package only — no `.xcodeproj`, no storyboards, no NIB files
- Target: macOS 13+
- No third-party dependencies — only Foundation, AppKit, Security frameworks
- Single executable target in `Package.swift`

## Architecture

Single file is fine. The app needs:

1. **NSStatusItem** — shows the text in the menu bar
2. **Keychain reader** — reads Claude Code's stored OAuth access token
3. **API poller** — calls the Anthropic usage endpoint with that token
4. **Timer** — refreshes every 60 seconds

## Keychain

Claude Code stores OAuth credentials in the macOS Keychain. Read the access token like this:

- Service name: `"Claude Code"`
- Account: any (enumerate all matches, pick the first valid one)
- Use `SecItemCopyMatching` with `kSecClassGenericPassword`

The token is a JWT. Use it as a Bearer token in API requests.

If the token is expired, attempt a refresh using the stored refresh token before giving up. The refresh endpoint is `https://claude.ai/api/auth/oauth/refresh` with `{"refresh_token": "<token>"}`.

## API

Endpoint used by claude-monitor (reverse engineered, not official):

```
GET https://claude.ai/api/organizations/<org_id>/usage
Authorization: Bearer <access_token>
```

To get org_id, first call:

```
GET https://claude.ai/api/auth/session
Authorization: Bearer <access_token>
```

Parse `memberships[0].organization.id` from the response.

The usage response contains:

```json
{
  "primary_usage_percent": 42.0,
  "primary_reset_at": "...",
  "weekly_usage_percent": 71.0,
  "weekly_reset_at": "..."
}
```

Use `primary_usage_percent` for S and `weekly_usage_percent` for W.

## Menu bar text format

```
S:42% W:71%
```

- Round to nearest integer
- If data is unavailable or loading: show `S:--% W:–-%`
- If token is missing: show `Claude: no auth`

## Error handling

- On network error: keep last known values, retry on next tick
- On 401: attempt token refresh once, then show `Claude: no auth`
- On any other error: show `S:--% W:–-%`, log to stderr

## Build & run

```bash
swift build
.build/debug/cc-menu
```

## Distribution (Homebrew)

After the app works, it will be distributed via a personal Homebrew tap.
The build script should produce a universal binary (arm64 + x86_64):

```bash
swift build -c release --arch arm64 --arch x86_64
```

The binary will be zipped and attached to a GitHub Release, then referenced
in a Homebrew cask formula in a separate `homebrew-tap` repo.

## What NOT to build

- No preferences window
- No popover on click
- No notifications
- No Sparkle / auto-update framework
- No LaunchAgent setup (user handles that manually)
