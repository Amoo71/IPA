import SwiftUI
import UIKit
import AVKit
import AVFoundation

/// Renders the media body of a message bubble (image, sticker, gif, video,
/// audio/voice, document). `path` is the decrypted local file once available.
struct MediaContent: View {
    let msg: Message
    let path: String?
    let accent: Color

    @State private var showVideo = false

    var body: some View {
        Group {
            switch msg.kind {
            case "image", "gif":
                imageView(maxW: 240, maxH: 300, rounded: true)
            case "sticker":
                imageView(maxW: 130, maxH: 130, rounded: false)
            case "video":
                videoView
            case "audio", "voice":
                AudioBubble(path: path, accent: accent, isVoice: msg.kind == "voice")
            case "document":
                documentView
            default:
                placeholder(label: msg.kind, icon: "doc")
            }
        }
    }

    // MARK: image / sticker / gif

    private func imageView(maxW: CGFloat, maxH: CGFloat, rounded: Bool) -> some View {
        Group {
            if let p = path, let ui = UIImage(contentsOfFile: p) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: maxW, maxHeight: maxH)
                    .clipShape(RoundedRectangle(cornerRadius: rounded ? 12 : 0))
            } else {
                placeholder(label: msg.kind == "sticker" ? "sticker" : "image", icon: "photo")
                    .frame(width: maxW, height: 160)
            }
        }
    }

    // MARK: video

    private var videoView: some View {
        Button { if path != nil { showVideo = true } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi)
                if path != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(accent)
                } else {
                    ProgressView().tint(accent)
                }
                VStack {
                    Spacer()
                    HStack {
                        Text("🎥 video").font(Theme.mono(10)).foregroundColor(Theme.textDim)
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: 240, height: 150)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showVideo) {
            if let p = path {
                VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: p)))
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: document

    private var documentView: some View {
        let name = msg.filename.isEmpty ? "document" : msg.filename
        return Group {
            if let p = path {
                ShareLink(item: URL(fileURLWithPath: p)) { docChip(name, ready: true) }
            } else {
                docChip(name, ready: false)
            }
        }
    }

    private func docChip(_ name: String, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill").foregroundColor(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.mono(12)).foregroundColor(Theme.text).lineLimit(1)
                Text(ready ? "tap to open" : "downloading…")
                    .font(Theme.mono(9)).foregroundColor(Theme.textFaint)
            }
        }
        .padding(10)
        .frame(maxWidth: 240, alignment: .leading)
        .background(Theme.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func placeholder(label: String, icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi)
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 26)).foregroundColor(Theme.textDim)
                Text(label).font(Theme.mono(9)).foregroundColor(Theme.textFaint)
            }
        }
    }
}

// MARK: - Audio

/// Minimal play/pause control for an audio or voice message.
struct AudioBubble: View {
    let path: String?
    let accent: Color
    let isVoice: Bool

    @StateObject private var player = AudioPlayerModel()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let p = path { player.toggle(path: p) }
            } label: {
                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(path == nil ? Theme.textFaint : accent)
            }
            .buttonStyle(.plain)
            .disabled(path == nil)

            Image(systemName: isVoice ? "waveform" : "music.note")
                .foregroundColor(Theme.textDim)
            Text(isVoice ? "voice message" : "audio")
                .font(Theme.mono(11)).foregroundColor(Theme.textDim)
        }
        .padding(10)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Theme.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

final class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    private var player: AVAudioPlayer?
    private var loadedPath: String?

    func toggle(path: String) {
        if playing {
            player?.pause()
            playing = false
            return
        }
        if player == nil || loadedPath != path {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player?.delegate = self
            loadedPath = path
        }
        player?.play()
        playing = true
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        playing = false
    }
}
