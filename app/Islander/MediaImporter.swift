import UIKit
import ImageIO

/// Decodes a picked image or GIF into individual PNG frames and writes them to
/// the shared App Group container so the widget can read them. A static image
/// yields one frame; an animated GIF yields up to `frameLimit` frames that the
/// app then cycles through by updating the Live Activity.
enum MediaImporter {
    static let frameLimit = 60

    static func framesDir(_ slot: String) -> URL? {
        guard let base = IslandShared.containerURL else { return nil }
        let dir = base.appendingPathComponent("frames/\(slot)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns the ordered list of frame file paths (empty on failure).
    static func importFrames(data: Data, slot: String) -> [String] {
        guard let dir = framesDir(slot) else { return [] }
        // Clear any previous frames for this slot.
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in old { try? FileManager.default.removeItem(at: f) }
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = max(1, CGImageSourceGetCount(src))
        let limit = min(count, frameLimit)
        var paths: [String] = []
        for i in 0..<limit {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let scaled = downscale(UIImage(cgImage: cg), maxDimension: 240)
            guard let png = scaled.pngData() else { continue }
            let url = dir.appendingPathComponent(String(format: "f%03d.png", i))
            do { try png.write(to: url); paths.append(url.path) } catch { continue }
        }
        return paths
    }

    static func clear(slot: String) {
        guard let dir = framesDir(slot) else { return }
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in old { try? FileManager.default.removeItem(at: f) }
        }
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let s = image.size
        let scale = min(1, maxDimension / max(s.width, s.height))
        if scale >= 1 { return image }
        let newSize = CGSize(width: s.width * scale, height: s.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
