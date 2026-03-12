import AppKit
import Darwin

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel!
    private var viewController: OverlayViewController!
    private var isVisible = false
    private let client = AeroSpaceClient()
    private var signalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        // Create panel
        panel = OverlayPanel()
        viewController = OverlayViewController()
        panel.contentViewController = viewController
        panel.onDismiss = { [weak self] in self?.dismiss() }

        viewController.onSelectWorkspace = { [weak self] name in
            self?.dismiss {
                self?.client.switchWorkspace(name)
            }
        }

        // Click-outside detection
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            // If click is outside the panel, dismiss
            if !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
        }

        // Setup SIGUSR1 handler
        setupSignalHandler()

        // Write PID file for easy signaling
        let pidPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/aerooverlay.pid").path
        let pidDir = (pidPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: pidDir, withIntermediateDirectories: true)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let pidPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/aerooverlay.pid").path
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    private func setupSignalHandler() {
        signal(SIGUSR1, SIG_IGN) // Ignore default behavior
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            self?.toggle()
        }
        source.resume()
        signalSource = source // Retain to prevent deallocation
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    private func show() {
        viewController.reload()
        panel.showOverlay()
        isVisible = true
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        guard isVisible else {
            completion?()
            return
        }
        isVisible = false
        panel.hideOverlay(completion: completion)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
