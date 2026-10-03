// SharedDataManager.swift
import Foundation
import SQLite3

public class SharedDataManager {
    public static let shared = SharedDataManager()
    
    public let dbManager: SQLiteManager
    public let dictQuery: DictionaryQuery
    
    private var fullShapeMap: [String: String] = [:]
    private var halfShapeMap: [String: String] = [:]
    
    private let fallbackFullShape: [String: String] = [
        "`": "｀", "~": "～", "!": "！", "@": "＠", "#": "＃", "$": "￥", "%": "％",
        "^": "……", "&": "＆", "*": "×", "(": "（", ")": "）", "_": "——", "+": "＋",
        "-": "－", "=": "＝", "[": "【", "]": "】", "{": "｛", "}": "｝", "|": "｜",
        "\\": "、", "/": "、", ";": "；", "'": "‘", ",": "，", ".": "。", "<": "《",
        ">": "》", "?": "？"
    ]
    
    private init() {
        // 架构级优化：使用 Bundle(for:) 兼容 iOS Extension Bundle 资源读取
        let bundle = Bundle(for: SharedDataManager.self)
        let dbPath = bundle.path(forResource: "HeMa", ofType: "db") ?? Bundle.main.path(forResource: "HeMa", ofType: "db") ?? ""
        
        if dbPath.isEmpty {
            Logger.shared.log(event: "FATAL_ERROR", details: "Database file 'HeMa.db' not found in bundle!")
        } else {
            Logger.shared.log(event: "INIT", details: "SharedDataManager Database path: \(dbPath)")
        }
        
        self.dbManager = SQLiteManager(databasePath: dbPath)
        
        let userDictPath = UserDictionaryManager.shared.getDatabasePath()
        if !userDictPath.isEmpty {
            self.dbManager.attachDatabase(path: userDictPath, as: "UserDB")
        }
        
        self.dictQuery = DictionaryQuery(dbManager: self.dbManager)
        
        if self.dbManager.testDatabase() {
            Logger.shared.log(event: "DB_INIT", details: "Database loaded and verified successfully.")
        } else {
            Logger.shared.log(event: "DB_INIT_ERROR", details: "Database verification failed. Please check HeMa.db.")
        }
        
        self.loadPunctuation()
    }
    
    private func loadPunctuation() {
        let query = "SELECT Key, FullShape, HalfShape FROM Punctuation;"
        if let stmt = dbManager.prepare(query: query) {
            var loadedCount = 0
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let keyCStr = sqlite3_column_text(stmt, 0),
                   let fullCStr = sqlite3_column_text(stmt, 1),
                   let halfCStr = sqlite3_column_text(stmt, 2) {
                    let key = String(cString: keyCStr)
                    self.fullShapeMap[key] = String(cString: fullCStr)
                    self.halfShapeMap[key] = String(cString: halfCStr)
                    loadedCount += 1
                }
            }
            dbManager.finalize(stmt: stmt)
            Logger.shared.log(event: "PUNC_INIT", details: "Loaded \(loadedCount) punctuations from DB.")
        }
        
        if self.fullShapeMap.isEmpty {
            Logger.shared.log(event: "PUNC_INIT", details: "Using fallback punctuation map.")
            self.fullShapeMap = self.fallbackFullShape
            self.halfShapeMap = self.fallbackFullShape
        }
    }
    
    public func isPunctuation(char: String) -> Bool {
        return self.fullShapeMap.keys.contains(char) || self.fallbackFullShape.keys.contains(char)
    }
    
    public func mapPunctuation(char: String) -> String {
        if let mapped = self.fullShapeMap[char] {
            return mapped
        }
        return char
    }
}