import AppKit
import Foundation

enum ClipboardCapture: Equatable {
    case text(String)
    case image(Data)
    case files([URL])
}

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var latestCapturedItem: ClipboardCapture?

    private let pasteboard: NSPasteboard
    private let markerType = NSPasteboard.PasteboardType("com.patgo.macbar.source")
    private let markerValue = "macbar"
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var lastKnownChangeCount: Int

    init(pasteboard: NSPasteboard = .general, pollInterval: TimeInterval = 0.6) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastKnownChangeCount = pasteboard.changeCount
    }

    var isMonitoring: Bool {
        timer != nil
    }

    func startMonitoring() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }

        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func copyTextToPasteboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString(markerValue, forType: markerType)
        lastKnownChangeCount = pasteboard.changeCount
    }

    func copyImageToPasteboard(_ imageTIFFData: Data) {
        pasteboard.clearContents()
        pasteboard.setData(imageTIFFData, forType: .tiff)
        pasteboard.setString(markerValue, forType: markerType)
        lastKnownChangeCount = pasteboard.changeCount
    }

    func copyFilesToPasteboard(_ fileURLs: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs as [NSURL])
        pasteboard.setString(markerValue, forType: markerType)
        lastKnownChangeCount = pasteboard.changeCount
    }

    private var lastCapturedFileURLs: [URL] = []

    private func pollPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastKnownChangeCount else {
            return
        }

        lastKnownChangeCount = currentChangeCount

        if pasteboard.string(forType: markerType) == markerValue {
            return
        }

        // Check for file URLs first (file copies often include text representations)
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            if urls != lastCapturedFileURLs {
                lastCapturedFileURLs = urls
                latestCapturedItem = .files(urls)
            }
            return
        }

        if let value = pasteboard.string(forType: .string),
           !value.isEmpty {
            latestCapturedItem = .text(value)
            return
        }

        guard let imageData = pasteboard.data(forType: .tiff), !imageData.isEmpty else {
            return
        }

        latestCapturedItem = .image(imageData)
    }
}
