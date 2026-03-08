import AppKit

@MainActor
final class AirDropService {
    private let service = NSSharingService(named: .sendViaAirDrop)

    func canSendFiles(_ fileURLs: [URL]) -> Bool {
        canPerform(with: fileURLs.map { $0 as Any })
    }

    func canSendImage(_ image: NSImage) -> Bool {
        canPerform(with: [image])
    }

    @discardableResult
    func sendFiles(_ fileURLs: [URL]) -> Bool {
        perform(with: fileURLs.map { $0 as Any })
    }

    @discardableResult
    func sendImage(_ image: NSImage) -> Bool {
        perform(with: [image])
    }

    private func canPerform(with items: [Any]) -> Bool {
        guard !items.isEmpty, let service else {
            return false
        }

        return service.canPerform(withItems: items)
    }

    private func perform(with items: [Any]) -> Bool {
        guard canPerform(with: items), let service else {
            return false
        }

        service.perform(withItems: items)
        return true
    }
}
