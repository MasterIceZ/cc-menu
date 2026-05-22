import Foundation

enum ClaudeError: Error {
    case unauthorized
    case badStatus(Int)
    case parseFailure
}

struct UsageData {
    let sessionPercent: Int
    let weeklyPercent: Int
    let sessionResetsAt: Date?
    let weeklyResetsAt: Date?
}

private let usageURL  = URL(string: "https://api.anthropic.com/api/oauth/usage")!
private let refreshURL = URL(string: "https://claude.ai/api/auth/oauth/refresh")!

private let isoParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

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

    return UsageData(
        sessionPercent: Int((fiveHour?["utilization"] as? Double ?? 0).rounded()),
        weeklyPercent:  Int((sevenDay?["utilization"]  as? Double ?? 0).rounded()),
        sessionResetsAt: (fiveHour?["resets_at"] as? String).flatMap { isoParser.date(from: $0) },
        weeklyResetsAt:  (sevenDay?["resets_at"]  as? String).flatMap { isoParser.date(from: $0) }
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
