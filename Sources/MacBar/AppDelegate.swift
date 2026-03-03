import AppKit
import SwiftUI

private final class MacBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private weak var observedPanelWindow: NSWindow?
    private let panelDetachedTopGap: CGFloat = 8
    private let defaultPanelSize = NSSize(width: 460, height: 620)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventMonitors()
        endObservingPanelWindow()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "MacBar")
        item.button?.action = #selector(togglePanel)
        item.button?.target = self
        statusItem = item
    }

    private func setupPanel() {
        let services = AppServices.shared

        let rootView = MenuBarRootView(
            store: services.store,
            localizationManager: services.localizationManager,
            navigator: services.navigator,
            onPreferredSizeChange: { [weak self] size in
                self?.updatePanelContentSize(size)
            }
        )
        .background(.regularMaterial)

        let panel = MacBarPanel(
            contentRect: NSRect(origin: .zero, size: defaultPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: rootView)

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 16
        panel.contentView?.layer?.masksToBounds = true

        self.panel = panel
    }

    @objc
    private func togglePanel() {
        guard let panel, let button = statusItem?.button else {
            return
        }

        if panel.isVisible {
            closePanel()
            return
        }

        showPanel(relativeTo: button)
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let panel else {
            return
        }

        positionPanel(relativeTo: button, panel: panel)
        statusItem?.button?.isHighlighted = true
        beginObservingPanelWindow(panel)
        startEventMonitors()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            self?.adjustPanelWindowToVisibleFrame()
        }
    }

    private func closePanel() {
        guard let panel, panel.isVisible else {
            return
        }

        panel.orderOut(nil)
        statusItem?.button?.isHighlighted = false
        stopEventMonitors()
        endObservingPanelWindow()
    }

    private func startEventMonitors() {
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
            ) { [weak self] event in
                self?.handleLocalEvent(event) ?? event
            }
        }

        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                guard let self else {
                    return
                }

                Task { @MainActor in
                    self.handleGlobalMouseDown()
                }
            }
        }
    }

    private func stopEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard let panel, panel.isVisible else {
            return event
        }

        if event.type == .keyDown, event.keyCode == 53 {
            closePanel()
            return nil
        }

        guard event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown else {
            return event
        }

        let location = event.window.map { window -> NSPoint in
            let pointInWindow = event.locationInWindow
            let pointRect = NSRect(origin: pointInWindow, size: .zero)
            return window.convertToScreen(pointRect).origin
        } ?? NSEvent.mouseLocation

        if panel.frame.contains(location) || statusButtonFrameOnScreen()?.contains(location) == true {
            return event
        }

        closePanel()
        return event
    }

    private func handleGlobalMouseDown() {
        guard let panel, panel.isVisible else {
            return
        }

        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) || statusButtonFrameOnScreen()?.contains(location) == true {
            return
        }

        closePanel()
    }

    private func statusButtonFrameOnScreen() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else {
            return nil
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonFrameInWindow)
    }

    private func beginObservingPanelWindow(_ window: NSWindow) {
        guard observedPanelWindow !== window else {
            return
        }

        endObservingPanelWindow()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelWindowFrameDidChange(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelWindowFrameDidChange(_:)),
            name: NSWindow.didChangeScreenNotification,
            object: window
        )
        observedPanelWindow = window
    }

    private func endObservingPanelWindow() {
        guard let window = observedPanelWindow else {
            return
        }

        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeScreenNotification,
            object: window
        )
        observedPanelWindow = nil
    }

    @objc
    private func panelWindowFrameDidChange(_ notification: Notification) {
        adjustPanelWindowToVisibleFrame()
    }

    private func updatePanelContentSize(_ size: CGSize) {
        guard let panel else {
            return
        }

        let clampedSize = NSSize(
            width: max(defaultPanelSize.width, size.width),
            height: max(defaultPanelSize.height, size.height)
        )

        guard panel.frame.size != clampedSize else {
            return
        }

        var frame = panel.frame
        frame.size = clampedSize
        panel.setFrame(frame, display: panel.isVisible)

        if let button = statusItem?.button {
            positionPanel(relativeTo: button, panel: panel)
        } else {
            adjustPanelWindowToVisibleFrame(panel)
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton, panel: NSPanel) {
        guard let buttonWindow = button.window else {
            adjustPanelWindowToVisibleFrame(panel)
            return
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        var frame = panel.frame
        frame.origin.x = buttonFrameOnScreen.midX - (frame.width / 2)
        frame.origin.y = buttonFrameOnScreen.minY - frame.height - panelDetachedTopGap
        panel.setFrame(frame, display: false)

        adjustPanelWindowToVisibleFrame(panel)
    }

    private func adjustPanelWindowToVisibleFrame(_ candidateWindow: NSWindow? = nil) {
        guard let window = candidateWindow ?? panel else {
            return
        }

        guard let screenFrame = window.screen?.visibleFrame else {
            return
        }

        var frame = window.frame
        let minX = screenFrame.minX
        let maxX = max(minX, screenFrame.maxX - frame.width)
        let minY = screenFrame.minY
        let maxY = max(minY, screenFrame.maxY - frame.height - panelDetachedTopGap)

        let clampedX = min(max(frame.origin.x, minX), maxX)
        let clampedY = min(max(frame.origin.y, minY), maxY)

        if frame.origin.x != clampedX || frame.origin.y != clampedY {
            frame.origin.x = clampedX
            frame.origin.y = clampedY
            window.setFrameOrigin(frame.origin)
        }
    }
}
