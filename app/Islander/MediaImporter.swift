import UIKit
import ImageIO
import AVFoundation

/// Result of importing a piece of media: the decoded frames (downscaled) and a
/// thumbnail. Frames are kept in memory and later encoded as tiny JPEGs that are
/// embedded directly into the Live Activity — so no App Group / file sharing is
/// needed and the island works regardless of how the app is signed.
struct ImportResult {
    var frames: [UIImage]
    var thumbnail: UIImage?
}

enum MediaImporter {
    static let frameLimit = 60
    /// Source frame size; the embedded JPEGs are encoded smaller to fit the
    /// Live Activity payload budget.
    static let sourceDimension: CGFloat = 120

    static func importMedia(data: Data) -> ImportResult {
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetType(src) != nil, CGImageSourceGetCount(src) >= 1 {
            return importImageSource(src)
        }
        return importVideo(data: data)
    }

    // MARK: image / gif

    private static func importImageSource(_ src: CGImageSource) -> ImportResult {
        let count = min(max(1, CGImageSourceGetCount(src)), frameLimit)
        var frames: [UIImage] = []
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(downscale(UIImage(cgImage: cg), maxDimension: sourceDimension))
        }
        return ImportResult(frames: frames, thumbnail: frames.first)
    }

    // MARK: video

    private static func importVideo(data: Data) -> ImportResult {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        guard (try? data.write(to: tmp)) != nil else { return ImportResult(frames: [], thumbnail: nil) }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let asset = AVURLAsset(url: tmp)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else { return ImportResult(frames: [], thumbnail: nil) }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: sourceDimension, height: sourceDimension)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let fps = 10.0
        let n = min(frameLimit, max(8, Int(duration * fps)))
        var frames: [UIImage] = []
        for i in 0..<n {
            let t = duration * Double(i) / Double(n)
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                frames.append(UIImage(cgImage: cg))
            }
        }
        return ImportResult(frames: frames, thumbnail: frames.first)
    }

    // MARK: helpers

    static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return image }
        let scale = min(1, maxDimension / max(s.width, s.height))
        if scale >= 1 { return image }
        let newSize = CGSize(width: s.width * scale, height: s.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    /// Encodes an image to a JPEG no larger than `maxBytes`, lowering quality then
    /// size as needed so it fits the Live Activity's ~4KB content budget.
    static func encode(_ image: UIImage, maxBytes: Int) -> Data? {
        for q in [CGFloat(0.5), 0.4, 0.3, 0.22] {
            if let d = image.jpegData(compressionQuality: q), d.count <= maxBytes { return d }
        }
        var dim: CGFloat = 64
        while dim >= 28 {
            let small = downscale(image, maxDimension: dim)
            if let d = small.jpegData(compressionQuality: 0.4), d.count <= maxBytes { return d }
            dim -= 12
        }
        return downscale(image, maxDimension: 28).jpegData(compressionQuality: 0.3)
    }
}
