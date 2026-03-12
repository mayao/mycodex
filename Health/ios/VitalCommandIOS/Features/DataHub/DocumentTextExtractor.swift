import Foundation
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
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
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
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
