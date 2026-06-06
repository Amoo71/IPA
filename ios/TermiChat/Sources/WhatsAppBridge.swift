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

    // Currently open conversation.
    @Published var openMessages: [Message] = []
    @Published var openProfile: Profile?
    private(set) var openJID: String?

    private(set) var lastPhone: String = ""   // phone used for current pairing attempt
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

    /// Selects the linking method after `need_pairing`. method = "qr" | "phone".
    func pair(method: String, phone: String = "") {
        if method == "phone" { lastPhone = phone }
        #if canImport(Wabridge)
        WabridgePair(method, phone)
        #endif
        if method == "phone" {
            DispatchQueue.main.async { self.state = .connecting }
        }
    }

    /// Requests a fresh 8-char pairing code for the same phone number.
    func requestNewCode() {
        #if canImport(Wabridge)
        WabridgeRequestNewCode(lastPhone)
        #endif
    }

    /// Tears down the current bridge and restarts it so the user can enter a
    /// different phone number. Emits `need_pairing` once the new bridge is up.
    func resetToChoosing() {
        #if canImport(Wabridge)
        WabridgeStop()
        #endif
        started = false
        DispatchQueue.main.async {
            self.logs = []
            self.state = .connecting
        }
        start()
    }

    func send(to jid: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if canImport(Wabridge)
        WabridgeSendText(jid, trimmed)
        #endif
    }

    /// Open a conversation: load history + fetch the contact/group profile.
    func openChat(_ jid: String) {
        openJID = jid
        openMessages = []
        openProfile = nil
        // Reading a chat clears its unread badge in the list.
        if let i = index[jid] { chats[i].unread = 0 }
        #if canImport(Wabridge)
        WabridgeOpenChat(jid)
        #endif
    }

    func closeChat() {
        openJID = nil
        openMessages = []
        openProfile = nil
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
        case "need_pairing":
            DispatchQueue.main.async {
                if case .online = self.state {} else { self.state = .choosing }
            }
        case "qr":
            if let code = obj["code"] as? String {
                DispatchQueue.main.async { self.state = .linking(qr: code) }
            }
        case "pair_code":
            if let code = obj["code"] as? String {
                DispatchQueue.main.async { self.state = .pairingCode(code: code) }
            }
        case "pair_error":
            let msg = (obj["error"] as? String) ?? "pairing failed"
            DispatchQueue.main.async {
                self.logs.append("pair_error: \(msg)")
                self.state = .choosing
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
            // Only treat as a reconnect blip when we were actually online;
            // don't disrupt the pairing screens.
            DispatchQueue.main.async {
                if case .online = self.state { self.state = .connecting }
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
        case "messages":
            if let jid = obj["jid"] as? String, let arr = obj["messages"] as? [[String: Any]] {
                let parsed = arr.compactMap { Self.decode(Message.self, $0) }
                DispatchQueue.main.async {
                    if jid == self.openJID { self.openMessages = parsed }
                }
            }
        case "new_message":
            if let d = obj["message"] as? [String: Any], let m = Self.decode(Message.self, d) {
                DispatchQueue.main.async {
                    if m.chatJid == self.openJID,
                       !self.openMessages.contains(where: { $0.rowKey == m.rowKey }) {
                        self.openMessages.append(m)
                    }
                }
            }
        case "profile":
            if let p = Self.decode(Profile.self, obj) {
                DispatchQueue.main.async {
                    if p.jid == self.openJID { self.openProfile = p }
                }
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
        decode(Chat.self, dict)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ dict: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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
extension WhatsAppBridge: WabridgeEventHandlerProtocol {
    @objc func handleEvent(_ json: String?) {
        guard let json else { return }
        handle(json)
    }
}
#endif
