// UserDictionaryManager.swift
import Foundation
import SQLite3

internal let SQLITE_TRANSIENT_USER = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public class UserDictionaryManager {
    public static let shared = UserDictionaryManager()
    private var db: OpaquePointer?
    private var dbPath: String = ""
    
    private init() {
        // 架构级优化：优先使用 App Group 共享目录，实现 iOS 跨进程词库共享
        let appDirectoryURL: URL
        if let sharedURL = AppConstants.sharedContainerURL {
            appDirectoryURL = sharedURL.appendingPathComponent("Database")
        } else {
            let fileManager = FileManager.default
            guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let bundleID = Bundle.main.bundleIdentifier ?? "com.hema.HeInput"
            appDirectoryURL = appSupportURL.appendingPathComponent(bundleID)
        }
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: appDirectoryURL.path) {
            try? fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let dbURL = appDirectoryURL.appendingPathComponent("UserDict.db")
        self.dbPath = dbURL.path
        
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            let createTableQuery = """
            CREATE TABLE IF NOT EXISTS UserPhrase (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                Word TEXT NOT NULL,
                Code TEXT NOT NULL,
                Weight INTEGER DEFAULT 1
            );
            """
            var errMsg: UnsafeMutablePointer<Int8>?
            sqlite3_exec(db, createTableQuery, nil, nil, &errMsg)
            
            let createWeightTableQuery = """
            CREATE TABLE IF NOT EXISTS SystemWordWeight (
                Word TEXT PRIMARY KEY,
                Weight INTEGER DEFAULT 0
            );
            """
            sqlite3_exec(db, createWeightTableQuery, nil, nil, &errMsg)
            
        } else {
            Logger.shared.log(event: "DB_ERROR", details: "Failed to open UserDict.db")
        }
    }
    
    public func getDatabasePath() -> String {
        return self.dbPath
    }
    
    public func increaseSystemWordWeight(word: String) {
        guard let db = db else { return }
        let query = """
        INSERT OR REPLACE INTO SystemWordWeight (Word, Weight) 
        VALUES (?, COALESCE((SELECT Weight FROM SystemWordWeight WHERE Word = ?), 0) + 10);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 2, (word as NSString).utf8String, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
    
    public func addOrUpdatePhrase(word: String, code: String) {
        guard let db = db else { return }
        let cleanCode = code.replacingOccurrences(of: " ", with: "")
        
        let query = "SELECT Id, Weight FROM UserPhrase WHERE Word = ? AND Code = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 2, (cleanCode as NSString).utf8String, -1, SQLITE_TRANSIENT_USER)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int(stmt, 0)
                let weight = sqlite3_column_int(stmt, 1)
                sqlite3_finalize(stmt)
                
                let updateQuery = "UPDATE UserPhrase SET Weight = ? WHERE Id = ?;"
                var updateStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, updateQuery, -1, &updateStmt, nil) == SQLITE_OK {
                    sqlite3_bind_int(updateStmt, 1, weight + 1)
                    sqlite3_bind_int(updateStmt, 2, id)
                    sqlite3_step(updateStmt)
                    sqlite3_finalize(updateStmt)
                }
            } else {
                sqlite3_finalize(stmt)
                let insertQuery = "INSERT INTO UserPhrase (Word, Code, Weight) VALUES (?, ?, 1);"
                var insertStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, insertQuery, -1, &insertStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(insertStmt, 1, (word as NSString).utf8String, -1, SQLITE_TRANSIENT_USER)
                    sqlite3_bind_text(insertStmt, 2, (cleanCode as NSString).utf8String, -1, SQLITE_TRANSIENT_USER)
                    sqlite3_step(insertStmt)
                    sqlite3_finalize(insertStmt)
                }
            }
        }
    }
    
    public func searchPrefix(code: String) -> [CandidateItem] {
        guard let db = db else { return [] }
        var results = [CandidateItem]()
        let query = "SELECT Word, Code FROM UserPhrase WHERE Code LIKE ? ORDER BY Weight DESC LIMIT 50;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            let searchStr = code + "%"
            sqlite3_bind_text(stmt, 1, (searchStr as NSString).utf8String, -1, SQLITE_TRANSIENT_USER)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let wStr = sqlite3_column_text(stmt, 0), let cStr = sqlite3_column_text(stmt, 1) {
                    let word = String(cString: wStr)
                    let c = String(cString: cStr)
                    results.append(CandidateItem(word: word, code: c))
                }
            }
            sqlite3_finalize(stmt)
        }
        return results
    }
    
    public func getAllPhrases() ->[(id: Int, word: String, code: String, weight: Int)] {
        guard let db = db else { return[] }
        var results = [(Int, String, String, Int)]()
        let query = "SELECT Id, Word, Code, Weight FROM UserPhrase ORDER BY Weight DESC;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                let word = String(cString: sqlite3_column_text(stmt, 1))
                let code = String(cString: sqlite3_column_text(stmt, 2))
                let weight = Int(sqlite3_column_int(stmt, 3))
                results.append((id, word, code, weight))
            }
            sqlite3_finalize(stmt)
        }
        return results
    }
    
    public func deletePhrase(id: Int) {
        guard let db = db else { return }
        let query = "DELETE FROM UserPhrase WHERE Id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(id))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
}