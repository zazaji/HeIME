// HeDataServer.swift
import Foundation
import SQLite3

public class HeDataServer {
    private let dictQuery: DictionaryQuery
    public let dbManager: SQLiteManager
    private var typedBuffer: String = ""
    
    public var allCandidates: [CandidateItem] = []
    public var currentPage: Int = 0
    public var selectedIndex: Int = 0
    public var prompt: String? = nil
    
    // 记录当前联想的完整前缀，用于连续联想
    public var associationPrefix: String = ""
    
    public var pageSize: Int {
        return PreferencesManager.shared.pageSize
    }
    
    public var currentCandidates: [CandidateItem] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, allCandidates.count)
        if start < end {
            return Array(allCandidates[start..<end])
        }
        return []
    }
    
    public init() {
        self.dbManager = SharedDataManager.shared.dbManager
        self.dictQuery = SharedDataManager.shared.dictQuery
    }
    
    public func appendCode(_ char: String, mode: InputMode) {
        let actualChar = char
        
        Logger.shared.log(event: "APPEND_CODE", details: "char: \(char), actualChar: \(actualChar), buffer: \(self.typedBuffer)")
        
        if self.typedBuffer.starts(with: "9") {
            let validChars = "0123456789"
            if validChars.contains(actualChar) {
                self.typedBuffer.append(actualChar)
                self.updateCandidates(mode: mode)
            }
            return
        }
        
        if mode == .heMaMode {
            if PreferencesManager.shared.isNumberMode {
                let validChars = "123450"
                if !validChars.contains(actualChar) { return }
                
                let letterCount = self.typedBuffer.filter { $0.isLetter }.count
                if letterCount >= 4 { return }
                
                self.typedBuffer.append(actualChar)
                
                if self.typedBuffer.count >= 2 && !self.typedBuffer.starts(with: "9") {
                    let lastTwo = String(self.typedBuffer.suffix(2))
                    if let letter = HeMaCore.codeToCharMap[lastTwo] {
                        self.typedBuffer.removeLast(2)
                        self.typedBuffer.append(letter)
                    }
                }
                self.updateCandidates(mode: mode)
                return
            } else {
                if self.typedBuffer.count >= 4 { return }
                let validChars = "abcdefghijklmnopqrstuvwxyz"
                if !validChars.contains(actualChar) { return }
            }
        }
        self.typedBuffer.append(actualChar)
        self.updateCandidates(mode: mode)
    }
    
    public func backspace(mode: InputMode) {
        if !self.typedBuffer.isEmpty {
            self.typedBuffer.removeLast()
            self.updateCandidates(mode: mode)
        }
    }
    
    public func clear() {
        self.typedBuffer = ""
        self.allCandidates.removeAll()
        self.currentPage = 0
        self.selectedIndex = 0
        self.prompt = nil
        self.associationPrefix = ""
    }
    
    public func getBuffer() -> String {
        return self.typedBuffer
    }
    
    public func setBuffer(_ buffer: String, mode: InputMode) {
        self.typedBuffer = buffer
        self.updateCandidates(mode: mode)
    }
    
    public func setAssociation(word: String) {
        self.typedBuffer = ""
        self.currentPage = 0
        self.selectedIndex = 0
        self.prompt = nil
        self.associationPrefix = word
        
        let mode = PreferencesManager.shared.currentMode
        self.allCandidates = self.dictQuery.searchAssociation(word: word, mode: mode, limit: 100)
    }
    
    public var hasIncompleteNumpadInput: Bool {
        var count = 0
        for char in self.typedBuffer.reversed() {
            if char.isNumber {
                count += 1
            } else {
                break
            }
        }
        return count.isMultiple(of: 2) == false
    }
    
    public func appendNumpadCode(_ char: String, mode: InputMode) {
        let validChars = "123450"
        if !validChars.contains(char) { return }
        
        let input = char == "0" ? "00" : char
        
        let letterCount = self.typedBuffer.filter { $0.isLetter }.count
        if letterCount >= 4 { return }
        
        self.typedBuffer.append(input)
        
        if self.typedBuffer.count >= 2 && !self.typedBuffer.starts(with: "9") {
            let lastTwo = String(self.typedBuffer.suffix(2))
            if let letter = HeMaCore.codeToCharMap[lastTwo] {
                self.typedBuffer.removeLast(2)
                self.typedBuffer.append(letter)
            }
        }
        self.updateCandidates(mode: mode)
    }
    
    public func cleanupIncompleteNumpadInput() {
        if self.hasIncompleteNumpadInput {
            self.typedBuffer.removeLast()
        }
        
        if self.typedBuffer.isEmpty {
            self.allCandidates.removeAll()
            self.currentPage = 0
            self.selectedIndex = 0
            self.prompt = nil
            self.associationPrefix = ""
        }
    }
    
    public func refreshCandidates(mode: InputMode) {
        if self.typedBuffer.isEmpty { return }
        self.updateCandidates(mode: mode)
    }
    
    public func pageUp() -> Bool {
        if self.currentPage > 0 {
            self.currentPage -= 1
            self.selectedIndex = 0
            return true
        }
        return false
    }
    
    public func pageDown() -> Bool {
        if (self.currentPage + 1) * self.pageSize < self.allCandidates.count {
            self.currentPage += 1
            self.selectedIndex = 0
            return true
        }
        return false
    }
    
    public func moveSelectionUp() {
        if self.selectedIndex > 0 {
            self.selectedIndex -= 1
        } else if self.pageUp() {
            self.selectedIndex = self.currentCandidates.count - 1
        }
    }
    
    public func moveSelectionDown() {
        if self.selectedIndex < self.currentCandidates.count - 1 {
            self.selectedIndex += 1
        } else if self.pageDown() {
            self.selectedIndex = 0
        }
    }
    
    private func updateCandidates(mode: InputMode) {
        self.currentPage = 0
        self.selectedIndex = 0
        self.prompt = nil
        
        if self.typedBuffer.isEmpty {
            self.allCandidates.removeAll()
            return
        }
        
        if self.typedBuffer == "9" {
            let prefs = PreferencesManager.shared
            let simpText = prefs.isSimplified ? "切换到繁体" : "切换到简体"
            let modeText = prefs.currentMode == .heMaMode ? "切换到拼音" : "切换到和码"
            let numText = prefs.isNumberMode ? "切换到字母模式" : "切换到数字模式"
            let phraseText = prefs.enablePhrase ? "关闭词组输入" : "开启词组输入"
            
            self.allCandidates = [
                CandidateItem(word: "进入设置", code: "91", isCategory: false),
                CandidateItem(word: simpText, code: "92", isCategory: false),
                CandidateItem(word: modeText, code: "93", isCategory: false),
                CandidateItem(word: numText, code: "94", isCategory: false),
                CandidateItem(word: phraseText, code: "95", isCategory: false),
                CandidateItem(word: "特殊符号", code: "96", isCategory: true)
            ]
            return
        }
        
        if self.typedBuffer.starts(with: "96") {
            self.allCandidates = self.dictQuery.searchSpecial(buffer: self.typedBuffer, limit: 300)
            return
        }
        
        self.allCandidates = self.dictQuery.search(buffer: self.typedBuffer, mode: mode)
    }
    
    public func getReverseLookupText(for candidate: CandidateItem, mode: InputMode) -> String? {
        if candidate.isCategory || candidate.code.starts(with: "9") { return nil }
        
        let word = candidate.word
        if word.isEmpty { return nil }
        
        if mode == .heMaMode {
            let query = "SELECT PinYin, ShengDiao FROM HanZi_PinYin WHERE HanZi = ? LIMIT 5;"
            var pinyins = [String]()
            if let stmt = self.dbManager.prepare(query: query) {
                sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, SQLITE_TRANSIENT)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let pinyinCStr = sqlite3_column_text(stmt, 0) {
                        let pinyin = String(cString: pinyinCStr)
                        let shengdiao = sqlite3_column_int(stmt, 1)
                        let toneStr = shengdiao > 0 ? "\(shengdiao)" : ""
                        pinyins.append(pinyin + toneStr)
                    }
                }
                self.dbManager.finalize(stmt: stmt)
            }
            if !pinyins.isEmpty {
                return "拼音: " + pinyins.joined(separator: ", ")
            }
        } else if mode == .pinYinMode {
            let query = "SELECT M1, M2, M3, M4 FROM HanZi WHERE HanZi = ? LIMIT 1;"
            var codes = [String]()
            if let stmt = self.dbManager.prepare(query: query) {
                sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    for i in 0..<4 {
                        let val = sqlite3_column_int(stmt, Int32(i))
                        if val > 0 {
                            codes.append(String(val))
                        }
                    }
                }
                self.dbManager.finalize(stmt: stmt)
            }
            
            if codes.isEmpty && word.count > 1 {
                let cizuQuery = "SELECT M1, M2, M3, M4 FROM CiZu WHERE CiZu = ? LIMIT 1;"
                if let stmt = self.dbManager.prepare(query: cizuQuery) {
                    sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        for i in 0..<4 {
                            let val = sqlite3_column_int(stmt, Int32(i))
                            if val > 0 {
                                codes.append(String(val))
                            }
                        }
                    }
                    self.dbManager.finalize(stmt: stmt)
                }
            }
            
            if !codes.isEmpty {
                return "和码: " + codes.joined(separator: " ")
            }
        }
        return nil
    }
}