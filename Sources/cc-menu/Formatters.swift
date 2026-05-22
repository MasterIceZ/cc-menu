import Foundation

func formatRelative(_ date: Date) -> String {
    let secs = date.timeIntervalSinceNow
    guard secs > 0 else { return "now" }
    let h = Int(secs) / 3600
    let m = (Int(secs) % 3600) / 60
    if h > 0 { return "in \(h)h \(m)m" }
    return "in \(m)m"
}

let absoluteFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()
