import SwiftUI
import UIKit
import ImageIO

/// Decodes and renders a local image file with full support for animated
/// stickers and GIFs (WebP, animated WebP, GIF, PNG, JPEG). iOS' ImageIO can
/// decode all of these on-device, including animated WebP frames, which plain
/// `UIImage(contentsOfFile:)` does not animate. This is what makes WhatsApp
/// stickers actually show up (and move).
struct AnimatedImage: UIViewRepresentable {
    let path: String
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = contentMode
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        configure(v)
        return v
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.accessibilityIdentifier != path {
            configure(uiView)
        }
    }

    private func configure(_ v: UIImageView) {
        v.accessibilityIdentifier = path
        guard let img = AnimatedImage.load(path) else { return }
        if let frames = img.frames {
            v.animationImages = frames
            v.animationDuration = img.duration
            v.animationRepeatCount = 0
            v.image = frames.first
            v.startAnimating()
        } else {
            v.stopAnimating()
            v.animationImages = nil
            v.image = img.still
        }
    }

    struct Decoded { var still: UIImage?; var frames: [UIImage]?; var duration: TimeInterval }

    /// Loads a still image, or an animated one (frames + total duration) when the
    /// file contains multiple frames.
    static func load(_ path: String) -> Decoded? {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return UIImage(contentsOfFile: path).map { Decoded(still: $0, frames: nil, duration: 0) }
        }
        let count = CGImageSourceGetCount(src)
        if count <= 1 {
            if let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return Decoded(still: UIImage(cgImage: cg), frames: nil, duration: 0)
            }
            return UIImage(contentsOfFile: path).map { Decoded(still: $0, frames: nil, duration: 0) }
        }
        var frames: [UIImage] = []
        var total: TimeInterval = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            total += frameDuration(src, i)
        }
        if frames.isEmpty { return nil }
        if total <= 0 { total = Double(frames.count) / 15.0 }
        return Decoded(still: frames.first, frames: frames, duration: total)
    }

    private static func frameDuration(_ src: CGImageSource, _ index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        // Animated WebP exposes per-frame delays under its own dictionary.
        if let webp = props[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let d = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double, d > 0 { return d }
            if let d = webp[kCGImagePropertyWebPDelayTime] as? Double, d > 0 { return d }
        }
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let d = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, d > 0 { return d }
            if let d = gif[kCGImagePropertyGIFDelayTime] as? Double, d > 0 { return d }
        }
        return 0.1
    }
}
