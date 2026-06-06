import SwiftUI
import PhotosUI

/// Editor for appearance: accent, text & bubble colors, transparency and a
/// background (none / color / image / video). Used both per-chat (from the chat
/// header menu) and globally (from Settings, via `isGlobal`).
struct ChatThemeEditor: View {
    let jid: String
    let title: String
    var isGlobal: Bool = false

    @EnvironmentObject var chatTheme: ChatThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var style: ChatStyle
    @State private var customAccent: Bool
    @State private var customText: Bool
    @State private var customInBubble: Bool
    @State private var customOutBubble: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var applyToAll = false
    @State private var loading = false

    init(jid: String, title: String, initial: ChatStyle, isGlobal: Bool = false) {
        self.jid = jid
        self.title = title
        self.isGlobal = isGlobal
        _style = State(initialValue: initial)
        _customAccent = State(initialValue: initial.accentHex != nil)
        _customText = State(initialValue: initial.textHex != nil)
        _customInBubble = State(initialValue: initial.inBubbleHex != nil)
        _customOutBubble = State(initialValue: initial.outBubbleHex != nil)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Divider().overlay(Theme.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(isGlobal ? "// global appearance (all chats)"
                                      : "// customizing: \(title)")
                            .font(Theme.mono(11)).foregroundColor(Theme.textFaint)

                        accentSection
                        colorsSection
                        bubbleOpacitySection
                        backgroundSection

                        if !isGlobal {
                            Toggle(isOn: $applyToAll) {
                                Text("apply to all chats")
                                    .font(Theme.mono(12)).foregroundColor(Theme.text)
                            }
                            .tint(Theme.accent)
                        }

                        HStack(spacing: 10) {
                            Button { save() } label: {
                                Text("[ save ]")
                                    .font(Theme.mono(13, .bold)).foregroundColor(Theme.bg)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button { reset() } label: {
                                Text("[ reset ]")
                                    .font(Theme.mono(13)).foregroundColor(Theme.text)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(Theme.surfaceHi)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: pickerItem) { _ in loadPicked() }
    }

    private var topBar: some View {
        HStack {
            Text(isGlobal ? "$ global theme" : "$ chat theme")
                .font(Theme.mono(16, .bold)).foregroundColor(Theme.accent)
            Spacer()
            Button { dismiss() } label: {
                Text("[ close ]").font(Theme.mono(12)).foregroundColor(Theme.text)
            }
        }
        .padding(16)
    }

    // MARK: accent

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("accent").font(Theme.mono(10)).foregroundColor(Theme.textFaint)
            Toggle(isOn: $customAccent) {
                Text("custom accent").font(Theme.mono(12)).foregroundColor(Theme.text)
            }
            .tint(Theme.accent)
            .onChange(of: customAccent) { on in
                if !on { style.accentHex = nil }
                else if style.accentHex == nil { style.accentHex = Theme.accent.hexString }
            }
            if customAccent {
                ColorPicker(selection: accentBinding, supportsOpacity: false) {
                    Text("color").font(Theme.mono(12)).foregroundColor(Theme.text)
                }
            }
        }
    }

    // MARK: text + bubble colors

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("colors").font(Theme.mono(10)).foregroundColor(Theme.textFaint)

            colorToggle("custom text color", isOn: $customText,
                        hex: $style.textHex, binding: hexBinding($style.textHex))
            colorToggle("custom bubble (incoming)", isOn: $customInBubble,
                        hex: $style.inBubbleHex, binding: hexBinding($style.inBubbleHex))
            colorToggle("custom bubble (mine)", isOn: $customOutBubble,
                        hex: $style.outBubbleHex, binding: hexBinding($style.outBubbleHex))
        }
    }

    private func colorToggle(_ label: String, isOn: Binding<Bool>,
                             hex: Binding<String?>, binding: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                Text(label).font(Theme.mono(12)).foregroundColor(Theme.text)
            }
            .tint(Theme.accent)
            .onChange(of: isOn.wrappedValue) { on in
                if !on { hex.wrappedValue = nil }
                else if hex.wrappedValue == nil { hex.wrappedValue = Theme.text.hexString }
            }
            if isOn.wrappedValue {
                ColorPicker(selection: binding, supportsOpacity: false) {
                    Text("color").font(Theme.mono(11)).foregroundColor(Theme.textDim)
                }
            }
        }
    }

    // MARK: transparency

    private var bubbleOpacitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("bubble transparency").font(Theme.mono(10)).foregroundColor(Theme.textFaint)
            HStack {
                Slider(value: Binding(
                    get: { style.bubbleOpacity ?? 1.0 },
                    set: { style.bubbleOpacity = $0 }), in: 0.1...1.0)
                .tint(Theme.accent)
                Text(String(format: "%.0f%%", (style.bubbleOpacity ?? 1.0) * 100))
                    .font(Theme.mono(10)).foregroundColor(Theme.textDim).frame(width: 44)
            }
        }
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { style.accentHex.flatMap { Color(hex: $0) } ?? Theme.accent },
            set: { style.accentHex = $0.hexString }
        )
    }

    private func hexBinding(_ hex: Binding<String?>) -> Binding<Color> {
        Binding(
            get: { hex.wrappedValue.flatMap { Color(hex: $0) } ?? Theme.text },
            set: { hex.wrappedValue = $0.hexString }
        )
    }

    // MARK: background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("background").font(Theme.mono(10)).foregroundColor(Theme.textFaint)

            Picker("", selection: $style.bgKind) {
                Text("none").tag(ChatBgKind.none)
                Text("color").tag(ChatBgKind.color)
                Text("image").tag(ChatBgKind.image)
                Text("video").tag(ChatBgKind.video)
            }
            .pickerStyle(.segmented)

            switch style.bgKind {
            case .none:
                Text("transparent terminal background")
                    .font(Theme.mono(10)).foregroundColor(Theme.textFaint)
            case .color:
                ColorPicker(selection: bgColorBinding, supportsOpacity: false) {
                    Text("color").font(Theme.mono(12)).foregroundColor(Theme.text)
                }
            case .image, .video:
                PhotosPicker(selection: $pickerItem,
                             matching: style.bgKind == .video ? .videos : .images) {
                    Text(loading ? "[ loading… ]"
                         : (style.bgValue.isEmpty ? "[ pick \(style.bgKind == .video ? "video" : "image/gif/png") ]"
                            : "[ change \(style.bgKind == .video ? "video" : "image") ]"))
                        .font(Theme.mono(13)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Theme.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                }
                if !style.bgValue.isEmpty {
                    Text("selected ✓").font(Theme.mono(10)).foregroundColor(Theme.accent)
                }
                // Dim overlay so foreground text stays readable over media.
                VStack(alignment: .leading, spacing: 6) {
                    Text("background dim").font(Theme.mono(10)).foregroundColor(Theme.textFaint)
                    HStack {
                        Slider(value: Binding(
                            get: { style.bgDim ?? 0.35 },
                            set: { style.bgDim = $0 }), in: 0.0...0.85)
                        .tint(Theme.accent)
                        Text(String(format: "%.0f%%", (style.bgDim ?? 0.35) * 100))
                            .font(Theme.mono(10)).foregroundColor(Theme.textDim).frame(width: 44)
                    }
                }
            }
        }
    }

    private var bgColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: style.bgValue) ?? Theme.bg },
            set: { style.bgValue = $0.hexString }
        )
    }

    private func loadPicked() {
        guard let item = pickerItem else { return }
        loading = true
        let isVideo = style.bgKind == .video
        item.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                loading = false
                guard case .success(let data?) = result else { return }
                let ext = isVideo ? ".mp4" : ".img"
                if let path = chatTheme.saveBackgroundFile(data, ext: ext) {
                    style.bgValue = path
                }
            }
        }
    }

    private func save() {
        let target = (isGlobal || applyToAll) ? ChatThemeManager.globalKey : jid
        chatTheme.set(style, for: target)
        dismiss()
    }

    private func reset() {
        if isGlobal {
            chatTheme.clear(ChatThemeManager.globalKey)
        } else {
            chatTheme.clear(jid)
            if applyToAll { chatTheme.clear(ChatThemeManager.globalKey) }
        }
        dismiss()
    }
}
