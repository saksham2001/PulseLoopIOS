import UIKit
import CoreImage

enum ImageFilterService {
    static func lineArt(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let context = CIContext()

        let lineOverlay = ciImage.applyingFilter("CILineOverlay", parameters: [
            "inputNRNoiseLevel": 0.07,
            "inputNRSharpness": 0.71,
            "inputEdgeIntensity": 1.0,
            "inputThreshold": 0.1,
            "inputContrast": 50.0
        ])

        guard let cgImage = context.createCGImage(lineOverlay, from: lineOverlay.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }

    static func halftone(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let context = CIContext()

        let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.2
        ])

        let halftone = grayscale.applyingFilter("CICMYKHalftone", parameters: [
            "inputWidth": 4.0,
            "inputSharpness": 0.7,
            "inputAngle": 0.0
        ])

        guard let cgImage = context.createCGImage(halftone, from: halftone.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }

    static func blackWhite(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let context = CIContext()

        let bw = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.8,
            kCIInputBrightnessKey: 0.05
        ])

        guard let cgImage = context.createCGImage(bw, from: bw.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }
}
