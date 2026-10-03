// Models.swift
import Foundation

public struct AppConstants {
    // 架构级配置：统一定义 App Group Identifier，用于 iOS 主 App 和 Keyboard Extension 之间的数据共享
    public static let appGroupIdentifier = "group.hezi.inputmethod"
    
    public static var sharedUserDefaults: UserDefaults {
        return UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
    
    public static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}

public enum InputMode: Int {
    case heMaMode = 0
    case pinYinMode = 1
    case englishMode = 2
}

public struct CandidateItem: Equatable, Hashable, Identifiable {
    public let id = UUID()
    public let word: String
    public let code: String
    public let isCategory: Bool
    
    public init(word: String, code: String, isCategory: Bool = false) {
        self.word = word
        self.code = code
        self.isCategory = isCategory
    }
    
    public static func == (lhs: CandidateItem, rhs: CandidateItem) -> Bool {
        return lhs.word == rhs.word && lhs.code == rhs.code && lhs.isCategory == rhs.isCategory
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(word)
        hasher.combine(code)
        hasher.combine(isCategory)
    }
}

public enum KeyAction {
    case char(String)
    case numpadChar(String)
    case space
    case backspace
    case forwardDelete
    case enter
    case escape
    case tab
    case numberSelect(Int)
    case pageUp
    case pageDown
    case up
    case down
    case left
    case right
    case home
    case end
    case punctuation(String)
    case openPreferences
    case unknown
}

public enum InputMethodEvent {
    case commitText(String)
    case updateMarkedText(String, [CandidateItem], Int, String?, String?)
    case hideCandidates
}

public struct HeMaCore {
    public static let charToCodeMap: [Character: String] = [
        "a": "35", "b": "51", "c": "53", "d": "33", "e": "13",
        "f": "32", "g": "31", "h": "41", "i": "23", "j": "42",
        "k": "43", "l": "44", "m": "00",  "n": "45", "o": "24",
        "p": "25", "q": "15", "r": "12", "s": "34", "t": "11",
        "u": "22", "v": "52", "w": "14", "x": "54", "y": "21",
        "z": "55"
    ]
    
    public static let charToIntMap: [Character: Int] = {
        var map = [Character: Int]()
        for (k, v) in charToCodeMap {
            if let intV = Int(v) {
                map[k] = intV
            }
        }
        return map
    }()
    
    public static let codeToCharMap:[String: Character] = {
        var map = [String: Character]()
        for (k, v) in charToCodeMap {
            map[v] = k
        }
        return map
    }()
}

public enum CommandActionType {
    case openPreferences
    case toggleSimp
    case toggleMode
    case toggleNumber
    case togglePhrase
}

public class CommandTree {
    public static let shared = CommandTree()
    
    public func getAction(buffer: String) -> CommandActionType? {
        switch buffer {
        case "91": return .openPreferences
        case "92": return .toggleSimp
        case "93": return .toggleMode
        case "94": return .toggleNumber
        case "95": return .togglePhrase
        default: return nil
        }
    }
}