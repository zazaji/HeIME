// DictionaryQuery.swift
import Foundation
import SQLite3

internal let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public class DictionaryQuery {
    private let dbManager: SQLiteManager
    
    public init(dbManager: SQLiteManager) {
        self.dbManager = dbManager
    }
    
    public func search(buffer: String, mode: InputMode, limit: Int = 300) -> [CandidateItem] {
        var results = [CandidateItem]()
        var seenWords = Set<String>()
        
        if buffer.starts(with: "96") {
            return self.searchSpecial(buffer: buffer, limit: limit)
        }
        
        // 将 buffer 统一转换为数字编码，用于精准匹配用户自定义词库
        var numericBuffer = ""
        for char in buffer {
            if let code = HeMaCore.charToCodeMap[char] {
                numericBuffer += code
            } else if char.isNumber {
                numericBuffer += String(char)
            } else {
                numericBuffer += String(char)
            }
        }
        
        let userCandidates = UserDictionaryManager.shared.searchPrefix(code: numericBuffer)
        for cand in userCandidates {
            if !seenWords.contains(cand.word) {
                seenWords.insert(cand.word)
                results.append(cand)
            }
        }
        
        let sysCandidates: [CandidateItem]
        switch mode {
        case .heMaMode:
            sysCandidates = self.searchHeMa(buffer: buffer, limit: limit)
        case .pinYinMode:
            sysCandidates = self.searchPinYin(buffer: buffer, limit: limit)
        case .englishMode:
            sysCandidates = self.searchEnglish(buffer: buffer, limit: limit)
        }
        
        for cand in sysCandidates {
            if !seenWords.contains(cand.word) {
                seenWords.insert(cand.word)
                results.append(cand)
            }
        }
        
        return results
    }
    
    public func searchAssociation(word: String, mode: InputMode, limit: Int = 100) ->[CandidateItem] {
        var results = [CandidateItem]()
        var seenWords = Set<String>()
        
        // 1. 查用户词库
        let userQuery = "SELECT Word, Code FROM UserPhrase WHERE Word LIKE ? AND Word != ? ORDER BY Weight DESC LIMIT ?;"
        if let stmt = self.dbManager.prepare(query: userQuery) {
            let searchStr = word + "%"
            sqlite3_bind_text(stmt, 1, (searchStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, (word as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let wStr = sqlite3_column_text(stmt, 0), let cStr = sqlite3_column_text(stmt, 1) {
                    let w = String(cString: wStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    let c = String(cString: cStr)
                    
                    // 截取前缀，只保留联想的后缀部分
                    if w.hasPrefix(word) && w.count > word.count {
                        let suffix = String(w.dropFirst(word.count))
                        if !suffix.isEmpty && !seenWords.contains(suffix) {
                            seenWords.insert(suffix)
                            results.append(CandidateItem(word: suffix, code: c))
                        }
                    }
                }
            }
            self.dbManager.finalize(stmt: stmt)
        }
        
        // 2. 查系统词库 (仅限和码模式或拼音模式)
        if mode == .heMaMode || mode == .pinYinMode {
            let isSimp = PreferencesManager.shared.isSimplified
            let jianFanVal = isSimp ? 0 : 1
            
            let sysQuery = """
                SELECT c.CiZu, c.M1, c.M2, c.M3, c.M4 
                FROM CiZu c 
                LEFT JOIN UserDB.SystemWordWeight w ON c.CiZu = w.Word 
                WHERE c.CiZu LIKE ? AND c.CiZu != ? AND (c.JianFan = ? OR c.JianFan IS NULL) 
                ORDER BY c.HeMaOrder ASC, COALESCE(w.Weight, 0) DESC LIMIT ?;
            """
            if let stmt = self.dbManager.prepare(query: sysQuery) {
                let searchStr = word + "%"
                sqlite3_bind_text(stmt, 1, (searchStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, (word as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 3, Int32(jianFanVal))
                sqlite3_bind_int(stmt, 4, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(stmt, 0) {
                        let w = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // 截取前缀，只保留联想的后缀部分
                        if w.hasPrefix(word) && w.count > word.count {
                            let suffix = String(w.dropFirst(word.count))
                            if !suffix.isEmpty && !seenWords.contains(suffix) {
                                seenWords.insert(suffix)
                                var codes = [String]()
                                for i in 1...4 {
                                    let val = sqlite3_column_int(stmt, Int32(i))
                                    if val > 0 {
                                        codes.append(String(val))
                                    }
                                }
                                let codeStr = codes.joined(separator: " ")
                                results.append(CandidateItem(word: suffix, code: codeStr))
                            }
                        }
                    }
                }
                self.dbManager.finalize(stmt: stmt)
            }
        }
        
        return results
    }
    
    public func searchSpecial(buffer: String, limit: Int = 300) -> [CandidateItem] {
        var results = [CandidateItem]()
        
        let childQuery = "SELECT Char, IsCategory, Code FROM SpecialChar WHERE Code LIKE ? ORDER BY Weight DESC, Id ASC LIMIT ?;"
        if let stmt = self.dbManager.prepare(query: childQuery) {
            let searchStr = buffer + "_"
            sqlite3_bind_text(stmt, 1, (searchStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let charCStr = sqlite3_column_text(stmt, 0), let codeCStr = sqlite3_column_text(stmt, 2) {
                    let char = String(cString: charCStr)
                    let code = String(cString: codeCStr)
                    let isCategory = sqlite3_column_int(stmt, 1) == 1
                    results.append(CandidateItem(word: char, code: code, isCategory: isCategory))
                }
            }
            self.dbManager.finalize(stmt: stmt)
        }
        
        if results.isEmpty {
            let exactQuery = "SELECT Char, IsCategory, Code FROM SpecialChar WHERE Code = ? ORDER BY Weight DESC, Id ASC LIMIT ?;"
            if let stmt = self.dbManager.prepare(query: exactQuery) {
                sqlite3_bind_text(stmt, 1, (buffer as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let charCStr = sqlite3_column_text(stmt, 0), let codeCStr = sqlite3_column_text(stmt, 2) {
                        let char = String(cString: charCStr)
                        let code = String(cString: codeCStr)
                        let isCategory = sqlite3_column_int(stmt, 1) == 1
                        results.append(CandidateItem(word: char, code: code, isCategory: isCategory))
                    }
                }
                self.dbManager.finalize(stmt: stmt)
            }
        }
        
        Logger.shared.log(event: "SEARCH_SPECIAL", details: "Buffer: \(buffer), Found: \(results.count) items")
        return results
    }
    
    private func searchHeMa(buffer: String, limit: Int) -> [CandidateItem] {
        var results = [CandidateItem]()
        var seenWords = Set<String>()
        
        var numericStr = ""
        for char in buffer {
            if let code = HeMaCore.charToCodeMap[char] {
                numericStr += code
            } else if char.isNumber {
                numericStr += String(char)
            }
        }
        
        var codes = [Int]()
        var partialCode: Int? = nil
        
        var i = 0
        let chars = Array(numericStr)
        while i < chars.count {
            if i + 1 < chars.count {
                let c1 = chars[i]
                let c2 = chars[i+1]
                let val = Int(String(c1) + String(c2))!
                codes.append(val)
                i += 2
            } else {
                partialCode = Int(String(chars[i]))!
                i += 1
            }
        }
        
        if codes.isEmpty && partialCode == nil { return results }
        
        // 架构级优化：移除对通配符 0 的层级拆分循环，直接使用完整的 codes 进行一次精准查询，确保通配符严格生效
        self.executeQueryForCodes(codes: codes, partialCode: partialCode, limit: limit, results: &results, seen: &seenWords)
        
        return results
    }
    
    private func executeQueryForCodes(codes: [Int], partialCode: Int?, limit: Int, results: inout [CandidateItem], seen: inout Set<String>) {
        var conditions = [String]()
        var values = [Any]()
        
        for (index, code) in codes.enumerated() {
            if index >= 4 { break }
            if code == 0 {
                conditions.append("h.M\(index+1) > 0")
            } else if code % 10 == 0 {
                let base = code
                conditions.append("h.M\(index+1) >= ? AND h.M\(index+1) <= ?")
                values.append(base + 1)
                values.append(base + 9)
            } else {
                conditions.append("h.M\(index+1) = ?")
                values.append(code)
            }
        }
        
        if let partial = partialCode, codes.count < 4 {
            let col = "h.M\(codes.count + 1)"
            if partial == 0 {
                conditions.append("\(col) > 0")
            } else {
                conditions.append("\(col) >= ? AND \(col) <= ?")
                values.append(partial * 10)
                values.append(partial * 10 + 9)
            }
        }
        
        if conditions.isEmpty { return }
        
        let whereClause = conditions.joined(separator: " AND ")
        let isSimp = PreferencesManager.shared.isSimplified
        let hanziOrderField = isSimp ? "GBOrder" : "B5Order"
        let jianFanVal = isSimp ? 0 : 1
        
        let hzQuery = """
            SELECT h.HanZi, h.M1, h.M2, h.M3, h.M4 
            FROM HanZi h 
            LEFT JOIN UserDB.SystemWordWeight w ON h.HanZi = w.Word 
            WHERE \(whereClause) 
            ORDER BY CASE WHEN h.M4 > 0 THEN 4 WHEN h.M3 > 0 THEN 3 WHEN h.M2 > 0 THEN 2 ELSE 1 END ASC,
                     COALESCE(w.Weight, 0) DESC, h.\(hanziOrderField) ASC LIMIT ?;
        """
        self.executeSearchWithCode(query: hzQuery, parameters: values + [limit as Any], results: &results, seen: &seen)
        
        if PreferencesManager.shared.enablePhrase {
            let czWhereClause = conditions.map { $0.replacingOccurrences(of: "h.", with: "c.") }.joined(separator: " AND ")
            let czQuery = """
                SELECT c.CiZu, c.M1, c.M2, c.M3, c.M4 
                FROM CiZu c 
                LEFT JOIN UserDB.SystemWordWeight w ON c.CiZu = w.Word 
                WHERE \(czWhereClause) AND (c.JianFan = ? OR c.JianFan IS NULL) 
                ORDER BY CASE WHEN c.M4 > 0 THEN 4 WHEN c.M3 > 0 THEN 3 WHEN c.M2 > 0 THEN 2 ELSE 1 END ASC,
                         c.HeMaOrder ASC, COALESCE(w.Weight, 0) DESC LIMIT ?;
            """
            self.executeSearchWithCode(query: czQuery, parameters: values + [jianFanVal as Any, limit as Any], results: &results, seen: &seen)
        }
        
        let hzpWhereClause = conditions.map { $0.replacingOccurrences(of: "h.", with: "p.") }.joined(separator: " AND ")
        let hzpQuery = """
            SELECT p.HanZi, p.M1, p.M2, p.M3, p.M4 
            FROM HanZi_Plus p 
            LEFT JOIN UserDB.SystemWordWeight w ON p.HanZi = w.Word 
            WHERE \(hzpWhereClause) 
            ORDER BY CASE WHEN p.M4 > 0 THEN 4 WHEN p.M3 > 0 THEN 3 WHEN p.M2 > 0 THEN 2 ELSE 1 END ASC,
                     COALESCE(w.Weight, 0) DESC LIMIT ?;
        """
        self.executeSearchWithCode(query: hzpQuery, parameters: values + [limit as Any], results: &results, seen: &seen)
    }
    
    private func searchPinYin(buffer: String, limit: Int) -> [CandidateItem] {
        var results = [CandidateItem]()
        var seenWords = Set<String>()
        
        let exactQuery = "SELECT HanZiString FROM PinYin_HanZi WHERE PinYin = ? LIMIT 1;"
        if let stmt = self.dbManager.prepare(query: exactQuery) {
            sqlite3_bind_text(stmt, 1, (buffer as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let hanziString = String(cString: cStr)
                    let words = hanziString.map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    for word in words {
                        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanWord.isEmpty && !seenWords.contains(cleanWord) {
                            seenWords.insert(cleanWord)
                            results.append(CandidateItem(word: cleanWord, code: buffer))
                        }
                    }
                }
            }
            self.dbManager.finalize(stmt: stmt)
        }
        
        let likeQuery = "SELECT HanZi FROM HanZi_PinYin WHERE PinYin LIKE ? LIMIT ?;"
        let searchStr = buffer + "%"
        if let stmt = self.dbManager.prepare(query: likeQuery) {
            sqlite3_bind_text(stmt, 1, (searchStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let word = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !word.isEmpty && !seenWords.contains(word) {
                        seenWords.insert(word)
                        results.append(CandidateItem(word: word, code: buffer))
                    }
                }
            }
            self.dbManager.finalize(stmt: stmt)
        }
        
        return results
    }
    
    private func searchEnglish(buffer: String, limit: Int) -> [CandidateItem] {
        var results = [CandidateItem]()
        var seenWords = Set<String>()
        let query = """
            SELECT e.word 
            FROM English_Word e 
            LEFT JOIN UserDB.SystemWordWeight w ON e.word = w.Word 
            WHERE e.word LIKE ? 
            ORDER BY e.HeMaOrder ASC, COALESCE(w.Weight, 0) DESC LIMIT ?;
        """
        let searchStr = buffer + "%"
        self.executeSearch(query: query, parameters: [searchStr as Any, limit as Any], buffer: buffer, results: &results, seen: &seenWords)
        return results
    }
    
    private func executeSearch(query: String, parameters: [Any], buffer: String, results: inout [CandidateItem], seen: inout Set<String>) {
        if let stmt = self.dbManager.prepare(query: query) {
            for (index, val) in parameters.enumerated() {
                let bindIndex = Int32(index + 1)
                if let intVal = val as? Int {
                    sqlite3_bind_int(stmt, bindIndex, Int32(intVal))
                } else if let strVal = val as? String {
                    sqlite3_bind_text(stmt, bindIndex, (strVal as NSString).utf8String, -1, SQLITE_TRANSIENT)
                }
            }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let word = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !word.isEmpty && !seen.contains(word) {
                        seen.insert(word)
                        results.append(CandidateItem(word: word, code: buffer))
                    }
                }
            }
            self.dbManager.finalize(stmt: stmt)
        }
    }
    
    private func executeSearchWithCode(query: String, parameters: [Any], results: inout [CandidateItem], seen: inout Set<String>) {
        if let stmt = self.dbManager.prepare(query: query) {
            for (index, val) in parameters.enumerated() {
                let bindIndex = Int32(index + 1)
                if let intVal = val as? Int {
                    sqlite3_bind_int(stmt, bindIndex, Int32(intVal))
                } else if let strVal = val as? String {
                    sqlite3_bind_text(stmt, bindIndex, (strVal as NSString).utf8String, -1, SQLITE_TRANSIENT)
                }
            }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let word = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !word.isEmpty && !seen.contains(word) {
                        seen.insert(word)
                        
                        var codes = [String]()
                        for i in 1...4 {
                            let val = sqlite3_column_int(stmt, Int32(i))
                            if val > 0 {
                                codes.append(String(val))
                            }
                        }
                        let codeStr = codes.joined(separator: " ")
                        results.append(CandidateItem(word: word, code: codeStr))
                    }
                }
            }
            self.dbManager.finalize(stmt: stmt)
        }
    }
}