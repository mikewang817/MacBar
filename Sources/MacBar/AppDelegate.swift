import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu-bar utility without a dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}
