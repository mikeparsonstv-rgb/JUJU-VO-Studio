import SwiftUI
import AppKit

@main
struct VOStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("JUJU VO Studio", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
                .task { model.start() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Job…") { model.showNewJob = true }.keyboardShortcut("n")
                    .disabled(model.library == nil)
            }
            CommandGroup(after: .newItem) {
                Button("Open WAV…") { model.chooseWAVToOpen() }.keyboardShortcut("o")
                    .disabled(model.library == nil)
            }
        }
    }
}

/// Receives Finder / Dock "open with" WAVs, whether the app was closed or running.
/// URLs are queued until the library database is open (brief §7A.2).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { IncomingFiles.shared.receive(urls) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private var termSource: DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A plain `kill` (SIGTERM) quits like ⌘Q, so the Engineer's LLM server and the mic are shut down too.
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { NSApp.terminate(nil) }
        src.resume()
        termSource = src
    }
}

@MainActor
final class IncomingFiles {
    static let shared = IncomingFiles()
    private var pending: [URL] = []
    private var handler: (([URL]) -> Void)?

    func receive(_ urls: [URL]) {
        if let handler { handler(urls) } else { pending.append(contentsOf: urls) }
    }
    /// Called once the library is ready; drains anything that arrived during launch.
    func attach(_ handler: @escaping ([URL]) -> Void) {
        self.handler = handler
        if !pending.isEmpty { let urls = pending; pending = []; handler(urls) }
    }
    func detach() { handler = nil }
}
