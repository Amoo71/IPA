import Foundation
import Combine
#if canImport(Wabridge)
import Wabridge
#endif

/// Bridges the gomobile-generated `Wabridge` framework into SwiftUI land.
///
/// The Go side delivers every event as a JSON string through the
/// `WabridgeEventHandler` protocol; we decode and republish as observable state.
final class WhatsAppBridge: NSObject, ObservableObject {

    @Published var state: ConnState = .offline
    @Published private(set) var chats: [Chat] = []
    @Published var logs: [String] = []

    private var index: [String: Int] = [:]   // jid -> position in `chats`
    private var started = false

    /// App-private directory the Go side uses for its encrypted session DB.
    private lazy var dataDir: String = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }()

    func start() {
        guard !started else { return }
        started = true
        DispatchQueue.main.async { self.state = .connecting }
        #if canImport(Wabridge)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Blocks until Stop() is called on the Go side.
            WabridgeStart(self.dataDir, self)
        }
        #endif
    }

    func send(to jid: String, text: String) {
        #if canImport(Wabridge)
        WabridgeSendText(jid, text)
        #endif
    }

    func logout() {
        #if canImport(Wabridge)
        WabridgeLogout()
        WabridgeStop()
        #endif
        started = false
        DispatchQueue.main.async {
            self.chats = []
            self.index = [:]
            self.state = .offline
        }
    }

    // MARK: - Event decoding

    private func handle(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "qr":
            if let code = obj["code"] as? String {
                DispatchQueue.main.async { self.state = .linking(qr: code) }
            }
        case "connected", "pair_success":
            let name = (obj["pushName"] as? String) ?? ""
            let jid = (obj["jid"] as? String) ?? ""
            DispatchQueue.main.async { self.state = .online(name: name, jid: jid) }
        case "logged_out":
            DispatchQueue.main.async {
                self.chats = []; self.index = [:]; self.state = .offline; self.started = false
            }
        case "disconnected":
            DispatchQueue.main.async {
                if case .online = self.state {} else { self.state = .connecting }
            }
        case "contact":
            if let jid = obj["jid"] as? String, let name = obj["name"] as? String {
                DispatchQueue.main.async { self.renameChat(jid: jid, name: name) }
            }
        case "chats":
            if let arr = obj["chats"] as? [[String: Any]] {
                let parsed = arr.compactMap { Self.decodeChat($0) }
                DispatchQueue.main.async { self.mergeHistory(parsed) }
            }
        case "message", "chat_upsert":
            if let c = obj["chat"] as? [String: Any], let chat = Self.decodeChat(c) {
                DispatchQueue.main.async { self.upsertLive(chat) }
            }
        case "log":
            if let line = obj["line"] as? String {
                DispatchQueue.main.async {
                    self.logs.append(line)
                    if self.logs.count > 200 { self.logs.removeFirst(self.logs.count - 200) }
                }
            }
        default:
            break
        }
    }

    private static func decodeChat(_ dict: [String: Any]) -> Chat? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(Chat.self, from: data)
    }

    // MARK: - List mutation

    private func rebuildIndex() {
        index.removeAll(keepingCapacity: true)
        for (i, c) in chats.enumerated() { index[c.jid] = i }
    }

    private func mergeHistory(_ incoming: [Chat]) {
        for c in incoming {
            if let i = index[c.jid] {
                // Keep the newer of the two by timestamp.
                if c.timestamp >= chats[i].timestamp { chats[i] = c }
            } else {
                chats.append(c)
            }
        }
        sortAndIndex()
    }

    private func upsertLive(_ c: Chat) {
        if let i = index[c.jid] {
            var existing = chats[i]
            existing.lastMessage = c.lastMessage
            existing.timestamp = c.timestamp
            existing.fromMe = c.fromMe
            if !c.fromMe { existing.unread += c.unread }
            if !c.name.isEmpty && c.name != existing.jid { existing.name = c.name }
            chats[i] = existing
        } else {
            chats.append(c)
        }
        sortAndIndex()
    }

    private func renameChat(jid: String, name: String) {
        guard !name.isEmpty, let i = index[jid] else { return }
        if chats[i].name.isEmpty || chats[i].name == String(jid.split(separator: "@").first ?? "") {
            chats[i].name = name
        }
    }

    /// Pinned first, then by most-recent activity.
    private func sortAndIndex() {
        chats.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.timestamp > b.timestamp
        }
        rebuildIndex()
    }
}

// MARK: - Gomobile callback conformance

#if canImport(Wabridge)
extension WhatsAppBridge: WabridgeEventHandler {
    func handleEvent(_ json: String?) {
        guard let json else { return }
        handle(json)
    }
}
#endif
