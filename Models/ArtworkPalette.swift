import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ArtworkPalette {
    static func averageColor(from data: Data) async -> UIColor? {
        await Task.detached(priority: .utility) {
            guard let image = CIImage(data: data) else { return nil }
            let extent = image.extent
            guard extent.width > 0, extent.height > 0 else { return nil }

            let filter = CIFilter.areaAverage()
            filter.inputImage = image
            filter.extent = extent

            let context = CIContext(options: [.workingColorSpace: NSNull()])
            guard let output = filter.outputImage else { return nil }

            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(
                output,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: nil
            )

            return UIColor(
                red: CGFloat(bitmap[0]) / 255,
                green: CGFloat(bitmap[1]) / 255,
                blue: CGFloat(bitmap[2]) / 255,
                alpha: 1
            )
        }.value
    }
}
