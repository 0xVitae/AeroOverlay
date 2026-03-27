import AppKit

final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard
    static let didChangeNotification = Notification.Name("SettingsStoreDidChange")

    private enum Key: String {
        case doubleTapInterval
        case hotkeyKeyCode
        case hotkeyModifiers
        case hotkeyMode // "doubleTap", "bothOptions", "custom"
        case showClaudeUsage
        case showSystemStats
        case aerospacePath
    }

    enum HotkeyMode: String {
        case doubleTap = "doubleTap"
        case bothOptions = "bothOptions"
        case custom = "custom"
    }

    var hotkeyMode: HotkeyMode {
        get {
            if let raw = defaults.string(forKey: Key.hotkeyMode.rawValue),
               let mode = HotkeyMode(rawValue: raw) {
                return mode
            }
            // Migration: if hotkeyKeyCode exists, it's custom mode
            if defaults.object(forKey: Key.hotkeyKeyCode.rawValue) != nil {
                return .custom
            }
            return .doubleTap
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.hotkeyMode.rawValue)
            notify()
        }
    }

    var doubleTapInterval: TimeInterval {
        get { defaults.object(forKey: Key.doubleTapInterval.rawValue) as? TimeInterval ?? 0.25 }
        set { defaults.set(newValue, forKey: Key.doubleTapInterval.rawValue); notify() }
    }

    /// nil means "use double-tap Option" (the default)
    var hotkeyKeyCode: UInt16? {
        get {
            guard defaults.object(forKey: Key.hotkeyKeyCode.rawValue) != nil else { return nil }
            return UInt16(defaults.integer(forKey: Key.hotkeyKeyCode.rawValue))
        }
        set {
            if let v = newValue {
                defaults.set(Int(v), forKey: Key.hotkeyKeyCode.rawValue)
            } else {
                defaults.removeObject(forKey: Key.hotkeyKeyCode.rawValue)
            }
            notify()
        }
    }

    var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            guard defaults.object(forKey: Key.hotkeyModifiers.rawValue) != nil else { return [] }
            return NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Key.hotkeyModifiers.rawValue)))
        }
        set { defaults.set(Int(newValue.rawValue), forKey: Key.hotkeyModifiers.rawValue); notify() }
    }

    var showClaudeUsage: Bool {
        get { defaults.object(forKey: Key.showClaudeUsage.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showClaudeUsage.rawValue); notify() }
    }

    var showSystemStats: Bool {
        get { defaults.object(forKey: Key.showSystemStats.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showSystemStats.rawValue); notify() }
    }

    var aerospacePath: String {
        get { defaults.string(forKey: Key.aerospacePath.rawValue) ?? "/opt/homebrew/bin/aerospace" }
        set { defaults.set(newValue, forKey: Key.aerospacePath.rawValue); notify() }
    }

    /// Human-readable string for the current hotkey
    var hotkeyDisplayString: String {
        if hotkeyMode == .bothOptions { return "Left ⌥ + Right ⌥" }
        guard let keyCode = hotkeyKeyCode else { return "Double-tap Option" }
        var parts: [String] = []
        let mods = hotkeyModifiers
        if mods.contains(.control) { parts.append("\u{2303}") }
        if mods.contains(.option) { parts.append("\u{2325}") }
        if mods.contains(.shift) { parts.append("\u{21E7}") }
        if mods.contains(.command) { parts.append("\u{2318}") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined(separator: "")
    }

    /// Reset hotkey to default double-tap Option
    func clearHotkey() {
        defaults.removeObject(forKey: Key.hotkeyKeyCode.rawValue)
        defaults.removeObject(forKey: Key.hotkeyModifiers.rawValue)
        defaults.removeObject(forKey: Key.hotkeyMode.rawValue)
        defaults.synchronize()
        notify()
    }

    /// Set hotkey to Left Option + Right Option mode
    func setBothOptionsHotkey() {
        defaults.removeObject(forKey: Key.hotkeyKeyCode.rawValue)
        defaults.removeObject(forKey: Key.hotkeyModifiers.rawValue)
        defaults.set(HotkeyMode.bothOptions.rawValue, forKey: Key.hotkeyMode.rawValue)
        defaults.synchronize()
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
            51: "Delete", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 109: "F10",
            111: "F12", 113: "F14", 115: "Home", 116: "PgUp", 117: "Fwd Del",
            118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
            123: "Left", 124: "Right", 125: "Down", 126: "Up",
            36: "Return", 76: "Enter",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
