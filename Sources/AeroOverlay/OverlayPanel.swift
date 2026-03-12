import AppKit

final class OverlayPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onDismiss?()
        } else if let vc = contentViewController as? OverlayViewController {
            vc.handleKeyDown(event)
        } else {
            super.keyDown(with: event)
        }
    }

    func showOverlay() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Size the panel to ~70% of screen, centered
        let panelWidth = min(screenFrame.width * 0.7, 1200)
        let panelHeight = min(screenFrame.height * 0.7, 800)
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.midY - panelHeight / 2

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        // Fade in
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func hideOverlay(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}
