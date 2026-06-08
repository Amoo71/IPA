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
                VStack(spacing: 20) {
                    IslandPreview()
                    statusCard
                    presets
                    contentSection
                    placementSection
                    animationSection
                    styleSection
                    countdownSection
                    batterySection
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

    // MARK: status

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle().fill(island.running ? island.accent : Color.gray).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(island.running ? "live activity running" : "idle")
                    .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Text(island.enabled ? island.status : "Live Activities disabled in Settings")
                    .font(.caption).foregroundColor(.white.opacity(0.6)).lineLimit(2)
            }
            Spacer()
            if island.lowPower {
                Label("low power", systemImage: "battery.25")
                    .font(.caption2).foregroundColor(.yellow)
            }
            Button { island.refresh() } label: {
                Image(systemName: "arrow.clockwise").foregroundColor(island.accent)
            }
        }
        .panel()
    }

    // MARK: presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Preset.all) { p in
                        Button { island.applyPreset(p) } label: {
                            Text(p.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.white.opacity(0.07))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .panel()
    }

    // MARK: content (image / gif / video / text)

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("content")
            HStack(spacing: 12) {
                slotCard(title: "left", image: island.leftPreview, item: $leftItem,
                         text: Binding(get: { island.leftText }, set: { island.leftText = $0 })) {
                    island.clearMedia(left: true)
                }
                slotCard(title: "right", image: island.rightPreview, item: $rightItem,
                         text: Binding(get: { island.rightText }, set: { island.rightText = $0 })) {
                    island.clearMedia(left: false)
                }
            }
            Text("Each side can show a photo, GIF or video, a text/emoji, or the animation. Priority: media → text → animation. Media is embedded directly — no App Group needed.")
                .font(.caption2).foregroundColor(.white.opacity(0.5))
        }
        .panel()
    }

    private func slotCard(title: String, image: UIImage?, item: Binding<PhotosPickerItem?>,
                          text: Binding<String>, clear: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.6))
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06))
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24)).foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(height: 88).clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 8) {
                PhotosPicker(selection: item, matching: .any(of: [.images, .videos])) {
                    Text(image == nil ? "pick" : "change")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(island.accent.opacity(0.22)).foregroundColor(island.accent)
                        .clipShape(Capsule())
                }
                if image != nil {
                    Button(action: clear) {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08)).foregroundColor(.white).clipShape(Circle())
                    }
                }
            }
            TextField("", text: text, prompt: Text("text / emoji").foregroundColor(.white.opacity(0.4)))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: placement

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("placement")
            Picker("", selection: $island.side) {
                Text("left").tag(IslandSide.left)
                Text("right").tag(IslandSide.right)
                Text("both").tag(IslandSide.both)
            }
            .pickerStyle(.segmented)
        }
        .panel()
    }

    // MARK: animation (chips)

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("animation")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(IslandAnim.allCases, id: \.self) { a in
                        let on = island.anim == a
                        Button { island.anim = a } label: {
                            HStack(spacing: 5) {
                                Image(systemName: a.icon).font(.caption2)
                                Text(a.label).font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(on ? island.accent : Color.white.opacity(0.07))
                            .foregroundColor(on ? .black : .white)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            slider("speed", value: $island.speed, range: 0.3...2.0, fmt: "%.1f×")
        }
        .panel()
    }

    // MARK: style (accent + text)

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("style")
            ColorPicker(selection: $island.accent, supportsOpacity: false) {
                Text("accent color").foregroundColor(.white)
            }
            field("title", text: $island.title)
            field("subtitle", text: $island.subtitle)
        }
        .panel()
    }

    // MARK: countdown

    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $island.countdownOn) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("countdown timer").foregroundColor(.white)
                    Text("ticks live in the island with no battery cost")
                        .font(.caption2).foregroundColor(.white.opacity(0.5))
                }
            }
            .tint(island.accent)
            if island.countdownOn {
                Stepper(value: $island.countdownMinutes, in: 1...180, step: 1) {
                    Text("\(Int(island.countdownMinutes)) min").foregroundColor(.white)
                }
                .onChange(of: island.countdownMinutes) { _ in island.countdownOn = true }
            }
        }
        .panel()
    }

    // MARK: battery

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("battery")
            Picker("", selection: $island.smoothness) {
                ForEach(Smoothness.allCases) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
            Text("Lower = fewer updates = less battery. Updates pause automatically when you leave the app, and static content sends nothing at all.")
                .font(.caption2).foregroundColor(.white.opacity(0.5))

            Toggle(isOn: Binding(get: { island.micActive }, set: { island.setMic($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("react to sound (microphone)").foregroundColor(.white)
                    Text("only while the app is open").font(.caption2).foregroundColor(.white.opacity(0.5))
                }
            }
            .tint(island.accent)
            if island.micActive {
                slider("sensitivity", value: $island.sensitivity, range: 3...18, fmt: "%.0f")
            }
        }
        .panel()
    }

    // MARK: controls

    private var controls: some View {
        Group {
            if island.running {
                Button { island.stop() } label: { Text("Stop").bigButton(bg: Color.red.opacity(0.85), fg: .white) }
            } else {
                Button { island.start() } label: { Text("Start").bigButton(bg: island.accent, fg: .black) }
            }
        }
    }

    private var footer: some View {
        Text("Dynamic Island needs iPhone 14 Pro+ (iOS 16.2+) and a signed install (KSign). No special entitlements required — media is embedded in the Live Activity.")
            .font(.caption2).foregroundColor(.white.opacity(0.4))
            .multilineTextAlignment(.center).padding(.top, 4)
    }

    // MARK: helpers

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, fmt: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.6)).frame(width: 88, alignment: .leading)
            Slider(value: value, in: range).tint(island.accent)
            Text(String(format: fmt, value.wrappedValue)).font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.7)).frame(width: 40, alignment: .trailing)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
            .foregroundColor(.white).padding(10)
            .background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased()).font(.caption2.weight(.bold)).foregroundColor(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load(_ item: PhotosPickerItem?, left: Bool) {
        guard let item else { return }
        item.loadTransferable(type: Data.self) { result in
            guard case .success(let data?) = result else { return }
            DispatchQueue.main.async { island.setMedia(data, left: left) }
        }
    }
}

// MARK: - Faux island preview (animates locally via TimelineView)

private struct IslandPreview: View {
    @EnvironmentObject var island: IslandController

    var body: some View {
        VStack(spacing: 8) {
            Text("preview").font(.caption2.weight(.bold)).foregroundColor(.white.opacity(0.4))
            TimelineView(.animation) { _ in
                let s = island.buildState()
                let accent = island.accent
                ZStack {
                    Capsule().fill(Color.black).frame(height: 44).frame(maxWidth: 230)
                    HStack(spacing: 0) {
                        SlotView(state: s, leading: true, imageSize: 30, compact: true)
                            .frame(maxWidth: .infinity)
                        if s.timerEnd != nil || !s.title.isEmpty {
                            VStack(spacing: 0) {
                                if let end = s.timerEnd { CountdownText(end: end, color: accent, size: 13) }
                                else if !s.title.isEmpty {
                                    Text(s.title).font(.caption2).foregroundColor(.white).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Group {
                            if let end = s.timerEnd { CountdownText(end: end, color: accent, size: 13) }
                            else { SlotView(state: s, leading: false, imageSize: 30, compact: true) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 230, maxHeight: 30)
                }
                .frame(height: 56)
            }
        }
    }
}

// MARK: - Small style helpers

private extension View {
    func panel() -> some View {
        self.padding(16).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private extension Text {
    func bigButton(bg: Color, fg: Color) -> some View {
        self.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(bg).foregroundColor(fg).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
