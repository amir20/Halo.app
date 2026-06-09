import SwiftUI
import AppKit
import DiskKit

@main
struct DiskDialApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ScanModel()

    var body: some Scene {
        WindowGroup("Disk · Dial") {
            ContentView(model: model)
                .onAppear {
                    if model.root == nil {
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        model.scan(path: home)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// Makes the SwiftPM executable behave like a normal foreground app:
/// shows in the Dock and takes focus on launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
