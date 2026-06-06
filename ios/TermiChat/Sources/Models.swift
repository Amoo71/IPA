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

/// A single chat message (mirrors the Go `Message`).
struct Message: Codable, Equatable {
    let id: String
    let chatJid: String
    var text: String
    var timestamp: Int64
    var fromMe: Bool
    var sender: String
    var senderName: String
    var kind: String
    var caption: String = ""
    var mimetype: String = ""
    var filename: String = ""
    var hasMedia: Bool = false
    var mediaPath: String = ""

    var isMedia: Bool { hasMedia || kind != "text" }

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    var timeLabel: String {
        guard timestamp > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Stable key for ForEach (ids can be empty for optimistic local sends).
    var rowKey: String { id.isEmpty ? "\(timestamp)-\(text.hashValue)" : id }
}

/// Contact / group profile (mirrors the Go `profile` event).
struct Profile: Codable, Equatable {
    var jid: String
    var name: String?
    var about: String?
    var phone: String?
    var isGroup: Bool?
    var participants: Int?
    var pictureURL: String?
}

/// Connection lifecycle as understood by the UI layer.
enum ConnState: Equatable {
    case offline
    case connecting                 // session exists, dialing in
    case choosing                   // ask user: phone number or QR
    case linking(qr: String)        // show QR code
    case pairingCode(code: String)  // show phone pairing code
    case online(name: String, jid: String)
}
