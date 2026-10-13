import Foundation
import ImageIO
import Vision

/// A Vision feature print, wrapped so it can move between tasks. The observation is created once
/// and only ever read afterwards, which is why sharing it is safe.
struct FeaturePrint: @unchecked Sendable {
    let observation: VNFeaturePrintObservation

    /// Distance to another print: 0 is the same picture, larger is less alike.
    func distance(to other: FeaturePrint) -> Float? {
        var result: Float = 0
        do {
            try observation.computeDistance(&result, to: other.observation)
            return result
        } catch {
            return nil
        }
    }
}

enum ImageFeatures {
    /// Longest side of the picture handed to Vision. A feature print does not need more, and
    /// reading a 40-megapixel original into memory for each of thousands of files would.
    static let analysisSize = 480

    /// Feature print of the image at `url`, or nil if it cannot be read as an image.
    static func featurePrint(of url: URL) -> FeaturePrint? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour the camera's rotation
            kCGImageSourceThumbnailMaxPixelSize: analysisSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let request = VNGenerateImageFeaturePrintRequest()
        // Scale rather than crop, so two frames of one scene are not compared on different cut-outs.
        request.imageCropAndScaleOption = .scaleFill
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        return (request.results?.first as? VNFeaturePrintObservation).map(FeaturePrint.init)
    }
}
