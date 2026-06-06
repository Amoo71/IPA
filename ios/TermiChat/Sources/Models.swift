import Foundation

/// Mirrors the JSON `Chat` emitted by the Go bridge.
struct Chat: Codable, Identifiable, Equatable {
    let jid: String
    var name: String
    var lastMessage: String
    var timestamp: Int64
    var unread: Int
    var pinned: Bool
    var archived: Bool
    var muted: Bool
    var isGroup: Bool
    var fromMe: Bool

    var id: String { jid }

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    /// "12:34" today, "Mon" this week, otherwise "06/06".
    var timeLabel: String {
        guard timestamp > 0 else { return "" }
        let cal = Calendar.current
        let now = Date()
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if let days = cal.dateComponents([.day], from: date, to: now).day, days < 7 {
            f.dateFormat = "EEE"
        } else {
            f.dateFormat = "dd/MM"
        }
        return f.string(from: date)
    }

    /// Short display name fallback for header / rows.
    var display: String {
        if !name.isEmpty { return name }
        return String(jid.split(separator: "@").first ?? "")
    }
}

/// Connection lifecycle as understood by the UI layer.
enum ConnState: Equatable {
    case offline
    case linking(qr: String)        // show QR code
    case connecting                 // session exists, dialing in
    case online(name: String, jid: String)
}
