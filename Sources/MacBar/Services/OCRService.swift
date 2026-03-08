import Foundation
import ImageIO
import Vision

enum OCRError: LocalizedError {
    case imageConversionFailed
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "无法处理图片格式"
        case let .recognitionFailed(msg):
            return "OCR 识别失败：\(msg)"
        }
    }
}

actor OCRService {
    private enum OCRImageInput {
        case data(Data)
        case fileURL(URL)
    }

    private static let maxOCRPixelDimension = 2_200

    func recognize(imageData: Data) async throws -> String {
        try Self.performOCR(on: .data(imageData))
    }

    func recognize(fileURL: URL) async throws -> String {
        try Self.performOCR(on: .fileURL(fileURL))
    }

    private nonisolated static func performOCR(on input: OCRImageInput) throws -> String {
        guard let cgImage = makeCGImage(for: input) else {
            throw OCRError.imageConversionFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private nonisolated static func makeCGImage(for input: OCRImageInput) -> CGImage? {
        let imageSource: CGImageSource?

        switch input {
        case let .data(imageData):
            imageSource = CGImageSourceCreateWithData(imageData as CFData, nil)
        case let .fileURL(fileURL):
            imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil)
        }

        guard let imageSource else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxOCRPixelDimension,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) {
            return thumbnail
        }

        let fullImageOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateImageAtIndex(imageSource, 0, fullImageOptions as CFDictionary)
    }
}
