import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "MacBar")
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item
    }

    private func setupPopover() {
        let services = AppServices.shared

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 460, height: 620)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarRootView(
                store: services.store,
                localizationManager: services.localizationManager,
                navigator: services.navigator
            )
        )

        self.popover = popover
    }

    @objc
    private func togglePopover() {
        guard let popover, let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Ensure the popover's window accepts key events
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.isHighlighted = false
    }

    func popoverWillShow(_ notification: Notification) {
        statusItem?.button?.isHighlighted = true
    }
}
