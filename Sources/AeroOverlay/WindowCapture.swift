import AppKit
import CoreGraphics

final class WindowCapture {
    /// Capture a thumbnail of a specific window by CGWindowID.
    /// Returns nil if screen recording permission is denied or window not found.
    static func capture(windowID: CGWindowID, maxSize: CGSize = CGSize(width: 200, height: 140)) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        // Scale to fit within maxSize
        let scale = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height, 1.0)
        let targetSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)

        let nsImage = NSImage(cgImage: cgImage, size: targetSize)
        return nsImage
    }

    /// Get the app icon for a given app name via NSRunningApplication
    static func appIcon(for appName: String) -> NSImage? {
        let allApps = NSWorkspace.shared.runningApplications
        if let app = allApps.first(where: { $0.localizedName == appName }) {
            return app.icon
        }
        return nil
    }
}
