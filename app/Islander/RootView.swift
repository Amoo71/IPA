import SwiftUI
import UIKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject var island: IslandController

    @State private var leftItem: PhotosPickerItem?
    @State private var rightItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    preview
                    statusCard
                    contentSection
                    sideAndAnim
                    accentSection
                    micSection
                    controls
                    footer
                }
                .padding(18)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.06).ignoresSafeArea())
            .navigationTitle("Islander")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onChange(of: leftItem) { item in load(item, left: true) }
        .onChange(of: rightItem) { item in load(item, left: false) }
    }

    // MARK: live preview of the island (animates in-app via TimelineView)

    private var preview: View_Preview { View_Preview() }

    // MARK: status

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(island.running ? island.accent : Color.gray)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(island.running ? "live activity running" : "idle")
                    .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Text(island.enabled ? island.status : "Live Activities disabled in Settings")
                    .font(.caption).foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Button { island.refresh() } label: {
                Image(systemName: "arrow.clockwise").foregroundColor(island.accent)
            }
        }
        .panel()
    }

    // MARK: content (images / gifs)

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("content")
            HStack(spacing: 12) {
                imageSlot(title: "left", image: island.leftPreview, item: $leftItem) {
                    island.clearImage(left: true)
                }
                imageSlot(title: "right", image: island.rightPreview, item: $rightItem) {
                    island.clearImage(left: false)
                }
            }
            Text("Pick a photo or GIF for each side. GIFs animate (frame-by-frame) in the island.")
                .font(.caption2).foregroundColor(.white.opacity(0.5))
        }
        .panel()
    }

    private func imageSlot(title: String, image: UIImage?, item: Binding<PhotosPickerItem?>,
                           clear: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.6))
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06))
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26)).foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 8) {
                PhotosPicker(selection: item, matching: .images) {
                    Text(image == nil ? "pick" : "change")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(island.accent.opacity(0.22))
                        .foregroundColor(island.accent)
                        .clipShape(Capsule())
                }
                if image != nil {
                    Button(action: clear) {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08)).foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: side + animation

    private var sideAndAnim: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("placement")
            Picker("", selection: Binding(get: { island.side }, set: { island.side = $0; island.applyNow() })) {
                Text("left").tag(IslandSide.left)
                Text("right").tag(IslandSide.right)
                Text("both").tag(IslandSide.both)
            }
            .pickerStyle(.segmented)

            sectionTitle("animation")
            Picker("", selection: Binding(get: { island.anim }, set: { island.anim = $0; island.applyNow() })) {
                ForEach(IslandAnim.allCases, id: \.self) { a in
                    Text(a.label).tag(a)
                }
            }
            .pickerStyle(.segmented)
        }
        .panel()
    }

    // MARK: accent + text

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("style")
            ColorPicker(selection: Binding(get: { island.accent }, set: { island.accent = $0; island.applyNow() }),
                        supportsOpacity: false) {
                Text("accent color").foregroundColor(.white)
            }
            field("title", text: Binding(get: { island.title }, set: { island.title = $0; island.applyNow() }))
            field("subtitle", text: Binding(get: { island.subtitle }, set: { island.subtitle = $0; island.applyNow() }))
        }
        .panel()
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
            .foregroundColor(.white)
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: mic

    private var micSection: some View {
        Toggle(isOn: Binding(get: { island.micActive }, set: { island.setMic($0) })) {
            VStack(alignment: .leading, spacing: 1) {
                Text("react to sound (microphone)").foregroundColor(.white)
                Text("drives the animation from live audio while the app is open")
                    .font(.caption2).foregroundColor(.white.opacity(0.5))
            }
        }
        .tint(island.accent)
        .panel()
    }

    // MARK: controls

    private var controls: some View {
        HStack(spacing: 12) {
            if island.running {
                Button { island.stop() } label: {
                    Text("Stop").bigButton(bg: Color.red.opacity(0.85), fg: .white)
                }
            } else {
                Button { island.start() } label: {
                    Text("Start").bigButton(bg: island.accent, fg: .black)
                }
            }
        }
    }

    private var footer: some View {
        Text("The Dynamic Island only appears on iPhone 14 Pro and newer, and needs the app to be signed (KSign) with the App Group + Live Activities entitlements.")
            .font(.caption2).foregroundColor(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased()).font(.caption2.weight(.bold)).foregroundColor(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load(_ item: PhotosPickerItem?, left: Bool) {
        guard let item else { return }
        item.loadTransferable(type: Data.self) { result in
            guard case .success(let data?) = result else { return }
            DispatchQueue.main.async { island.setImage(data, left: left) }
        }
    }
}

// MARK: - Faux island preview (animates locally via TimelineView)

/// A black "island" capsule rendered at the top so the user previews their
/// configuration. Uses TimelineView so it animates smoothly inside the app
/// (regular apps aren't subject to the Live Activity animation limits).
private struct View_Preview: View {
    @EnvironmentObject var island: IslandController

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let state = previewState(t: t)
            VStack(spacing: 8) {
                Text("preview").font(.caption2.weight(.bold)).foregroundColor(.white.opacity(0.4))
                ZStack {
                    Capsule().fill(Color.black)
                        .frame(height: 44)
                        .frame(maxWidth: 220)
                    HStack {
                        slot(state: state, leading: true)
                        Spacer()
                        slot(state: state, leading: false)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 220)
                }
                .frame(height: 56)
            }
        }
    }

    private func previewState(t: Double) -> IslandAttributes.ContentState {
        let tick = t * 6
        let levels = (0..<7).map { i in 0.15 + 0.85 * pow(abs(sin(tick * 0.45 + Double(i) * 0.55)), 1.6) }
        var s = island.buildState()
        s.levels = island.micActive ? s.levels : levels
        s.phase = tick * 0.4
        return s
    }

    @ViewBuilder
    private func slot(state: IslandAttributes.ContentState, leading: Bool) -> some View {
        let active = leading ? (state.side == .left || state.side == .both)
                             : (state.side == .right || state.side == .both)
        let frame = leading ? island.leftPreview : island.rightPreview
        if !active {
            Color.clear.frame(width: 28, height: 28)
        } else if let frame {
            Image(uiImage: frame).resizable().scaledToFill()
                .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            AnimationView(anim: state.anim, levels: state.levels, phase: state.phase,
                          color: island.accent, compact: true)
                .frame(width: 38, height: 24)
        }
    }
}

// MARK: - Small style helpers

private extension View {
    func panel() -> some View {
        self.padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private extension Text {
    func bigButton(bg: Color, fg: Color) -> some View {
        self.font(.headline)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(bg).foregroundColor(fg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
