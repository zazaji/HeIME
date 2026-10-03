// PunctuationMapper.swift
import Foundation

public class PunctuationMapper {
    private var quoteToggle = false
    private var singleQuoteToggle = false
    private var angleBracketNest = 0
    
    public init() {
    }
    
    public func isPunctuation(char: String) -> Bool {
        return SharedDataManager.shared.isPunctuation(char: char)
    }
    
    public func map(char: String, mode: InputMode) -> String {
        if mode == .englishMode {
            return char
        }
        
        // 动态处理成对标点
        switch char {
        case "\"":
            let ret = self.quoteToggle ? "”" : "“"
            self.quoteToggle.toggle()
            return ret
        case "'":
            let ret = self.singleQuoteToggle ? "’" : "‘"
            self.singleQuoteToggle.toggle()
            return ret
        case "<":
            let ret = self.angleBracketNest == 0 ? "《" : "〈"
            self.angleBracketNest += 1
            return ret
        case ">":
            self.angleBracketNest = max(0, self.angleBracketNest - 1)
            let ret = self.angleBracketNest == 0 ? "》" : "〉"
            return ret
        default:
            break
        }
        
        return SharedDataManager.shared.mapPunctuation(char: char)
    }
}