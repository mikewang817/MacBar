import SwiftUI

@main
struct MacBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hiddenMenu: Bool = false

    var body: some Scene {
        MenuBarExtra("", isInserted: $hiddenMenu) {
            EmptyView()
        }
    }
}
