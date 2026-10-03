// KeyHandler.swift
#if os(macOS)
import Cocoa
import Carbon.HIToolbox

public class KeyHandler {
    private let puncMapper: PunctuationMapper
    
    public init(puncMapper: PunctuationMapper) {
        self.puncMapper = puncMapper
    }
    
    public func parse(event: NSEvent) -> KeyAction {
        let keyCode = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        if flags.contains(.control) && flags.contains(.option) && keyCode == 35 {
            return .openPreferences
        }
        
        if keyCode == kVK_Delete { return .backspace }
        if keyCode == kVK_ForwardDelete { return .forwardDelete }
        if keyCode == kVK_Space { return .space }
        if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter { return .enter }
        if keyCode == kVK_Escape { return .escape }
        if keyCode == kVK_Tab { return .tab }
        if keyCode == kVK_Home { return .home }
        if keyCode == kVK_End { return .end }
        
        if keyCode == kVK_PageUp || 
           keyCode == kVK_ANSI_Minus || 
           keyCode == kVK_ANSI_LeftBracket { 
            return .pageUp 
        }
        
        if keyCode == kVK_PageDown || 
           keyCode == kVK_ANSI_Equal || 
           keyCode == kVK_ANSI_RightBracket { 
            return .pageDown 
        }
        
        if keyCode == kVK_UpArrow { return .up }
        if keyCode == kVK_DownArrow { return .down }
        if keyCode == kVK_LeftArrow { return .left }
        if keyCode == kVK_RightArrow { return .right }
        
        guard let chars = event.charactersIgnoringModifiers,
              let firstChar = chars.first 
        else {
            return .unknown
        }
        
        let charStr = String(firstChar)
        
        let numpadKeyCodes: Set<Int> = [82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93]
        if numpadKeyCodes.contains(keyCode) {
            return .numpadChar(charStr)
        }
        
        if let num = Int(charStr), num >= 0 && num <= 9 {
            if PreferencesManager.shared.isNumberMode {
                if num >= 1 && num <= 5 {
                    return .char(charStr)
                } else if num == 0 {
                    return .char(charStr)
                }
            }
            if num >= 1 && num <= 9 {
                return .numberSelect(num)
            } else if num == 0 {
                return .char("0")
            }
        }
        
        if self.puncMapper.isPunctuation(char: charStr) {
            return .punctuation(charStr)
        }
        
        if charStr.rangeOfCharacter(from: .letters) != nil {
            return .char(charStr.lowercased())
        }
        
        return .unknown
    }
}
#endif