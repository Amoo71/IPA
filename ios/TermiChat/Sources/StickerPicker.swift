import SwiftUI

/// A grid of stickers the user has received or saved (the .webp files in the
/// media cache). Tapping one sends it. This is the in-app "sticker keyboard".
struct StickerPickerView: View {
    let onPick: (String) -> Void

    @EnvironmentObject var wa: WhatsAppBridge
    @Environment(\.dismiss) private var dismiss

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    @State private var files: [String] = []

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("$ stickers").font(Theme.mono(16, .bold)).foregroundColor(Theme.accent)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("[ close ]").font(Theme.mono(12)).foregroundColor(Theme.text)
                    }
                }
                .padding(16)
                Divider().overlay(Theme.line)

                if files.isEmpty {
                    VStack(spacing: 8) {
                        Text("// no stickers yet")
                            .font(Theme.mono(13)).foregroundColor(Theme.textFaint)
                        Text("stickers you receive or save\nappear here to re-send")
                            .font(Theme.mono(10)).foregroundColor(Theme.textFaint)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 10) {
                            ForEach(files, id: \.self) { p in
                                Button {
                                    onPick(p)
                                    dismiss()
                                } label: {
                                    AnimatedImage(path: p)
                                        .frame(width: 72, height: 72)
                                        .background(Theme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { files = wa.stickerFiles() }
    }
}
