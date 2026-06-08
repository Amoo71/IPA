import UIKit
import ImageIO
import AVFoundation

/// Result of importing a piece of media.
struct ImportResult {
    var paths: [String]       // ordered frame file paths (for the widget)
    var thumbnail: UIImage?   // first frame, for the app's picker thumbnail
    var appGroupOK: Bool      // false => widget can't read frames; preview still works
}

/// Decodes a picked photo, GIF or video into PNG frames written to the shared
/// App Group container so the widget can render them. Static image → one frame;
/// animated GIF → its frames; video → frames sampled across its duration.
///
/// If the App Group container isn't available (app not yet signed with the
/// entitlement), frames are written to the app's own caches as a fallback so the
/// in-app preview still works — `appGroupOK` reports which happened.
enum MediaImporter {
    static let frameLimit = 60

    private static func baseDir() -> (url: URL, appGroup: Bool)? {
        if let g = IslandShared.containerURL { return (g, true) }
        if let c = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true) {
            return (c, false)
        }
        return nil
    }

    private static func framesDir(_ slot: String) -> (url: URL, appGroup: Bool)? {
        guard let base = baseDir() else { return nil }
        let dir = base.url.appendingPathComponent("frames/\(slot)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, base.appGroup)
    }

    static func clear(slot: String) {
        guard let d = framesDir(slot) else { return }
        if let old = try? FileManager.default.contentsOfDirectory(at: d.url, includingPropertiesForKeys: nil) {
            for f in old { try? FileManager.default.removeItem(at: f) }
        }
    }

    static func importMedia(data: Data, slot: String) -> ImportResult {
        // Image / GIF if ImageIO recognises it; otherwise treat as a video.
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetType(src) != nil, CGImageSourceGetCount(src) >= 1 {
            return importImageSource(src, slot: slot)
        }
        return importVideo(data: data, slot: slot)
    }

    // MARK: image / gif

    private static func importImageSource(_ src: CGImageSource, slot: String) -> ImportResult {
        guard let d = framesDir(slot) else { return ImportResult(paths: [], thumbnail: nil, appGroupOK: false) }
        wipe(d.url)
        let count = min(max(1, CGImageSourceGetCount(src)), frameLimit)
        var paths: [String] = []
        var thumb: UIImage?
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let img = downscale(UIImage(cgImage: cg), maxDimension: 240)
            if thumb == nil { thumb = img }
            if let path = write(img, to: d.url, index: i) { paths.append(path) }
        }
        return ImportResult(paths: paths, thumbnail: thumb, appGroupOK: d.appGroup)
    }

    // MARK: video

    private static func importVideo(data: Data, slot: String) -> ImportResult {
        guard let d = framesDir(slot) else { return ImportResult(paths: [], thumbnail: nil, appGroupOK: false) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        guard (try? data.write(to: tmp)) != nil else {
            return ImportResult(paths: [], thumbnail: nil, appGroupOK: d.appGroup)
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let asset = AVURLAsset(url: tmp)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            return ImportResult(paths: [], thumbnail: nil, appGroupOK: d.appGroup)
        }
        wipe(d.url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 240)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let fps = 10.0
        let n = min(frameLimit, max(8, Int(duration * fps)))
        var paths: [String] = []
        var thumb: UIImage?
        for i in 0..<n {
            let t = duration * Double(i) / Double(n)
            let time = CMTime(seconds: t, preferredTimescale: 600)
            guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { continue }
            let img = UIImage(cgImage: cg)
            if thumb == nil { thumb = img }
            if let path = write(img, to: d.url, index: i) { paths.append(path) }
        }
        return ImportResult(paths: paths, thumbnail: thumb, appGroupOK: d.appGroup)
    }

    // MARK: helpers

    private static func wipe(_ dir: URL) {
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in old { try? FileManager.default.removeItem(at: f) }
        }
    }

    private static func write(_ image: UIImage, to dir: URL, index: Int) -> String? {
        guard let png = image.pngData() else { return nil }
        let url = dir.appendingPathComponent(String(format: "f%03d.png", index))
        do { try png.write(to: url); return url.path } catch { return nil }
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
