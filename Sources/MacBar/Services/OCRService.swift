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
    func recognize(imageData: Data) async throws -> String {
        try Self.performOCR(on: imageData)
    }

    private nonisolated static func performOCR(on imageData: Data) throws -> String {
        guard
            let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
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
}
