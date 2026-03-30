import Foundation
import CoreImage
import PDFKit
import UniformTypeIdentifiers
import Vision
import UIKit

enum DocumentTextExtractor {
    static func extractText(
        from url: URL,
        data: Data,
        contentType: UTType?
    ) async -> String? {
        if contentType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return extractPDFText(data: data)
        }

        if contentType?.conforms(to: .image) == true {
            return await extractImageText(data: data)
        }

        if contentType?.conforms(to: .plainText) == true ||
            contentType?.conforms(to: .commaSeparatedText) == true ||
            contentType?.conforms(to: .json) == true {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    private static func extractPDFText(data: Data) -> String? {
        guard let document = PDFDocument(data: data) else {
            return nil
        }

        let text = (0 ..< document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    private static func extractImageText(data: Data) async -> String? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let variants = makeOCRImageVariants(from: image)
        var bestText: String?

        for variant in variants {
            guard let recognizedText = await recognizeText(in: variant) else {
                continue
            }

            if score(for: recognizedText) > score(for: bestText) {
                bestText = recognizedText
            }
        }

        return bestText
    }

    private static func recognizeText(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text?.isEmpty == false ? text : nil)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private static func makeOCRImageVariants(from image: UIImage) -> [UIImage] {
        let normalized = normalizeOrientation(of: image)
        let scaled = scaleForOCR(normalized)
        let enhanced = highContrastImage(from: scaled) ?? scaled
        let grayscale = grayscaleImage(from: scaled) ?? enhanced
        return [scaled, enhanced, grayscale]
    }

    private static func normalizeOrientation(of image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func scaleForOCR(_ image: UIImage) -> UIImage {
        let maxDimension = max(image.size.width, image.size.height)
        guard maxDimension < 2200 else {
            return image
        }

        let scale = 2200.0 / maxDimension
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func highContrastImage(from image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else {
            return nil
        }

        guard let filter = CIFilter(name: "CIColorControls") else {
            return nil
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(1.35, forKey: kCIInputContrastKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        filter.setValue(0.1, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage else {
            return nil
        }

        return renderUIImage(from: output)
    }

    private static func grayscaleImage(from image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else {
            return nil
        }

        guard let filter = CIFilter(name: "CIPhotoEffectNoir") else {
            return nil
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        guard let output = filter.outputImage else {
            return nil
        }

        return renderUIImage(from: output)
    }

    private static func renderUIImage(from ciImage: CIImage) -> UIImage? {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }

    private static func score(for text: String?) -> Int {
        guard let text else {
            return 0
        }

        let lineCount = text.split(separator: "\n").count
        let digitCount = text.filter(\.isNumber).count
        return text.count + (lineCount * 12) + (digitCount * 2)
    }
}
