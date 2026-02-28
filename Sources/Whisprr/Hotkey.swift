import AppKit
import Foundation

enum Hotkey: Codable, Equatable {
    case soloModifier(keyCode: UInt16, modifierFlag: UInt)
    case combination(keyCode: UInt16, modifiers: UInt)

    static let defaultHotkey: Hotkey = .soloModifier(keyCode: 54, modifierFlag: NSEvent.ModifierFlags.command.rawValue)

    // MARK: - Persistence

    private static let userDefaultsKey = "hotkey"

    static func load() -> Hotkey {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return .defaultHotkey
        }
        return hotkey
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Hotkey.userDefaultsKey)
        }
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .soloModifier(let keyCode, _):
            return keyCodeName(keyCode)
        case .combination(let keyCode, let modifiers):
            let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
            var parts: [String] = []
            // Standard macOS modifier order: Fn ⌃ ⌥ ⇧ ⌘
            if flags.contains(.function) { parts.append("Fn") }
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            parts.append(keyCodeName(keyCode))
            return parts.joined()
        }
    }

    // MARK: - Key Code Names

    private func keyCodeName(_ keyCode: UInt16) -> String {
        // Modifier keys with left/right distinction
        switch keyCode {
        // Command
        case 55: return "Left ⌘"
        case 54: return "Right ⌘"
        // Shift
        case 56: return "Left ⇧"
        case 60: return "Right ⇧"
        // Option
        case 58: return "Left ⌥"
        case 61: return "Right ⌥"
        // Control
        case 59: return "Left ⌃"
        case 62: return "Right ⌃"
        // Fn
        case 63: return "Fn"
        default: break
        }

        // Letters A-Z (key codes 0-50 region)
        let letters: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
            12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
        ]
        if let letter = letters[keyCode] { return letter }

        // Numbers 0-9
        let numbers: [UInt16: String] = [
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
            23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        ]
        if let number = numbers[keyCode] { return number }

        // F-keys
        let fkeys: [UInt16: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15",
        ]
        if let fkey = fkeys[keyCode] { return fkey }

        // Special keys
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            117: "⌦",
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
            41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        ]
        if let s = special[keyCode] { return s }

        return "Key\(keyCode)"
    }
}
