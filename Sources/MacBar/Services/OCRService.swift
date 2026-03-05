import AppKit
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

@MainActor
final class OCRService {
    func recognize(nsImage: NSImage) async throws -> String {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageConversionFailed
        }
        return try await Task.detached(priority: .userInitiated) {
            try Self.performOCR(on: cgImage)
        }.value
    }

    private nonisolated static func performOCR(on cgImage: CGImage) throws -> String {
        var result = ""
        var recognitionError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNRecognizeTextRequest { req, err in
            defer { semaphore.signal() }
            if let err {
                recognitionError = err
                return
            }
            let observations = req.results as? [VNRecognizedTextObservation] ?? []
            result = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            recognitionError = error
        }
        semaphore.wait()

        if let recognitionError {
            throw OCRError.recognitionFailed(recognitionError.localizedDescription)
        }
        return result
    }
}
