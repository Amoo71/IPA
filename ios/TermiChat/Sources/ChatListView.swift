import SwiftUI

struct ChatListView: View {
    let name: String
    let jid: String

    @EnvironmentObject var wa: WhatsAppBridge
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var chatTheme: ChatThemeManager
    @State private var query: String = ""
    @State private var showArchived = false
    @State private var showSettings = false
    @State private var selected: Chat?

    private var displayName: String {
        name.isEmpty ? String(jid.split(separator: "@").first ?? "me") : name
    }

    /// Active (non-archived) chats, filtered by the search query.
    private var visible: [Chat] {
        wa.chats.filter { c in
            let archMatch = showArchived ? c.archived : !c.archived
            guard archMatch else { return false }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return c.display.lowercased().contains(q) || c.lastMessage.lowercased().contains(q)
        }
    }

    private var pinned: [Chat]  { visible.filter { $0.pinned } }
    private var regular: [Chat] { visible.filter { !$0.pinned } }
    private var archivedCount: Int { wa.chats.filter { $0.archived }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            searchBar
            if !showArchived && archivedCount > 0 {
                archivedRow
            }
            if showArchived { archivedBanner }
            chatScroll
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView(name: displayName, jid: jid)
                .environmentObject(wa)
                .environmentObject(theme)
                .environmentObject(chatTheme)
        }
        .fullScreenCover(item: $selected) { chat in
            ChatDetailView(chat: chat)
                .environmentObject(wa)
                .environmentObject(theme)
                .environmentObject(chatTheme)
        }
    }

    private func row(_ chat: Chat) -> some View {
        Button { selected = chat } label: {
            ChatRow(chat: chat, avatarURL: wa.avatars[chat.jid])
        }
        .buttonStyle(.plain)
        .onAppear { wa.loadAvatar(chat.jid) }
    }

    // MARK: connected as: <name>   [settings]

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("connected as:")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textDim)
                Text(displayName)
                    .font(Theme.mono(16, .bold))
                    .foregroundColor(Theme.accent)
                    .lineLimit(1)
            }
            Spacer()
            Button { showSettings = true } label: {
                Text("[ settings ]")
                    .font(Theme.mono(12))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceHi)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: centered rounded search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(Theme.mono(14, .bold))
                .foregroundColor(Theme.accent)
            TextField("", text: $query, prompt: Text("search").foregroundColor(Theme.textFaint))
                .font(Theme.mono(14))
                .foregroundColor(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textFaint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: archived entry

    private var archivedRow: some View {
        Button { withAnimation { showArchived = true } } label: {
            HStack(spacing: 10) {
                Text("▤")
                    .font(Theme.mono(15))
                    .foregroundColor(Theme.textDim)
                Text("archived")
                    .font(Theme.mono(13))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("\(archivedCount)")
                    .font(Theme.mono(12))
                    .foregroundColor(Theme.textDim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var archivedBanner: some View {
        Button { withAnimation { showArchived = false } } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left").font(.system(size: 11))
                Text("archived").font(Theme.mono(13, .bold))
                Spacer()
            }
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: list

    private var chatScroll: some View {
        List {
            Group {
                if visible.isEmpty {
                    emptyState
                } else {
                    if !pinned.isEmpty {
                        sectionLabel("pinned")
                        ForEach(pinned) { row($0) }
                    }
                    if !regular.isEmpty {
                        if !pinned.isEmpty { sectionLabel("chats") }
                        ForEach(regular) { row($0) }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable {
            wa.refresh()
            // Keep the spinner up briefly so the pull feels responsive.
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        HStack {
            Text("── \(s) " + String(repeating: "─", count: max(0, 28 - s.count)))
                .font(Theme.mono(10))
                .foregroundColor(Theme.textFaint)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(query.isEmpty ? "// syncing chats…" : "// no matches")
                .font(Theme.mono(13))
                .foregroundColor(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Row

private struct ChatRow: View {
    let chat: Chat
    var avatarURL: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: avatarURL, name: chat.display, isGroup: chat.isGroup, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if chat.pinned {
                        Text("📌").font(.system(size: 10))
                    }
                    Text(chat.display)
                        .font(Theme.mono(14, .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    if chat.muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textFaint)
                    }
                    Spacer()
                    Text(chat.timeLabel)
                        .font(Theme.mono(10))
                        .foregroundColor(chat.unread > 0 ? Theme.accent : Theme.textFaint)
                }
                HStack(spacing: 6) {
                    Text(preview)
                        .font(Theme.mono(12))
                        .foregroundColor(Theme.textDim)
                        .lineLimit(1)
                    Spacer()
                    if chat.unread > 0 {
                        Text("\(chat.unread)")
                            .font(Theme.mono(10, .bold))
                            .foregroundColor(Theme.bg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.badge)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var preview: String {
        let body = chat.lastMessage.isEmpty ? "—" : chat.lastMessage
        return chat.fromMe ? "you: \(body)" : body
    }
}
