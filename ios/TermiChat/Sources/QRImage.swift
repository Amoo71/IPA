import SwiftUI
import CoreImage.CIFilterBuiltins

/// Renders a crisp, scaled QR code from an arbitrary string.
enum QR {
    static func image(from string: String, scale: CGFloat = 10) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        if let output = filter.outputImage {
            let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let cg = context.createCGImage(transformed, from: transformed.extent) {
                return Image(decorative: cg, scale: 1, orientation: .up)
            }
        }
        return Image(systemName: "qrcode")
    }
}
