import AppKit
import Darwin

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel!
    private var viewController: OverlayViewController!
    private var settingsPanel: SettingsPanel!
    private var settingsVC: SettingsViewController!
    private var isVisible = false
    private var isSettingsVisible = false
    private let client = AeroSpaceClient()
    private var signalSource: DispatchSourceSignal?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private var lastOptionKeyDown: Date?
    private var settingsObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        // Create overlay panel
        panel = OverlayPanel()
        viewController = OverlayViewController()
        panel.contentViewController = viewController
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.onOpenSettings = { [weak self] in self?.showSettings() }

        viewController.onSelectWorkspace = { [weak self] name in
            OverlayNotifications.clear(workspace: name)
            self?.dismiss {
                self?.client.switchWorkspace(name)
            }
        }

        // Create settings panel
        settingsPanel = SettingsPanel()
        settingsVC = SettingsViewController()
        settingsPanel.contentViewController = settingsVC
        settingsPanel.onDismiss = { [weak self] in self?.dismissSettings() }

        // Click-outside detection
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            if self.isSettingsVisible && !self.settingsPanel.frame.contains(NSEvent.mouseLocation) {
                self.dismissSettings()
                return
            }
            if self.isVisible && !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
        }

        // Setup key monitors
        setupKeyMonitors()

        // Observe settings changes to rebuild hotkey monitors
        settingsObserver = NotificationCenter.default.addObserver(
            forName: SettingsStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.setupKeyMonitors()
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

    // MARK: - Settings

    private func showSettings() {
        guard !isSettingsVisible else { return }
        isSettingsVisible = true
        settingsPanel.showSettings()
    }

    private func dismissSettings() {
        guard isSettingsVisible else { return }
        isSettingsVisible = false
        settingsPanel.hideSettings { [weak self] in
            // Reload overlay to reflect any changed settings
            if self?.isVisible == true {
                self?.viewController.reload()
                // Resize panel to fit potentially changed content
                if let panel = self?.panel, let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    panel.setFrame(NSRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height), display: false)
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let fittingSize = panel.contentView?.fittingSize ?? CGSize(width: 600, height: 400)
                    let panelWidth = min(fittingSize.width + 40, screenFrame.width * 0.9)
                    let panelHeight = min(fittingSize.height + 40, screenFrame.height * 0.9)
                    let x = screenFrame.midX - panelWidth / 2
                    let y = screenFrame.midY - panelHeight / 2
                    panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
                }
                self?.panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Key Monitors

    private func setupKeyMonitors() {
        // Remove existing monitors
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if let m = globalHotkeyMonitor { NSEvent.removeMonitor(m); globalHotkeyMonitor = nil }
        if let m = localHotkeyMonitor { NSEvent.removeMonitor(m); localHotkeyMonitor = nil }

        let settings = SettingsStore.shared
        if let keyCode = settings.hotkeyKeyCode {
            // Custom hotkey mode
            let requiredMods = settings.hotkeyModifiers
            setupCustomHotkeyMonitor(keyCode: keyCode, modifiers: requiredMods)
        } else {
            // Default: double-tap Option
            setupOptionKeyMonitor()
        }
    }

    private func handleOptionKey() {
        if isVisible {
            dismiss()
            lastOptionKeyDown = nil
            return
        }
        let now = Date()
        let interval = SettingsStore.shared.doubleTapInterval
        if let last = self.lastOptionKeyDown, now.timeIntervalSince(last) < interval {
            self.lastOptionKeyDown = nil
            self.show()
        } else {
            self.lastOptionKeyDown = now
        }
    }

    private func setupOptionKeyMonitor() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            if event.modifierFlags.contains(.option) {
                self.handleOptionKey()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            if event.modifierFlags.contains(.option) {
                self.handleOptionKey()
            }
            return event
        }
    }

    private func setupCustomHotkeyMonitor(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == keyCode && event.modifierFlags.intersection([.control, .option, .shift, .command]) == modifiers {
                self.toggle()
            }
        }

        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == keyCode && event.modifierFlags.intersection([.control, .option, .shift, .command]) == modifiers {
                self.toggle()
                return nil // consume the event
            }
            return event
        }
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
        // Also dismiss settings if open
        if isSettingsVisible {
            isSettingsVisible = false
            settingsPanel.hideSettings()
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
