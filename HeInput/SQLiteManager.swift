// SQLiteManager.swift
import Foundation
import SQLite3

public class SQLiteManager {
    private var db: OpaquePointer?
    
    public init(databasePath: String) {
        self.openDatabase(path: databasePath)
    }
    
    deinit {
        if let db = self.db {
            sqlite3_close(db)
            Logger.shared.log(event: "DB_CLOSE", details: "Database closed.")
        }
    }
    
    private func openDatabase(path: String) {
        if sqlite3_open(path, &self.db) == SQLITE_OK {
            Logger.shared.log(event: "DB_OPEN", details: "Success: \(path)")
        } else {
            let errMsg = String(cString: sqlite3_errmsg(self.db))
            Logger.shared.log(event: "DB_ERROR", details: "Failed: \(errMsg)")
        }
    }
    
    // 架构级新增：支持挂载外部数据库，实现跨库联合查询
    public func attachDatabase(path: String, as name: String) {
        let query = "ATTACH DATABASE '\(path)' AS \(name);"
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(self.db, query, nil, nil, &errMsg) == SQLITE_OK {
            Logger.shared.log(event: "DB_ATTACH", details: "Successfully attached \(path) as \(name)")
        } else {
            let errStr = errMsg != nil ? String(cString: errMsg!) : "Unknown error"
            Logger.shared.log(event: "DB_ATTACH_ERROR", details: "Failed to attach \(path): \(errStr)")
        }
    }
    
    public func prepare(query: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, query, -1, &stmt, nil) == SQLITE_OK {
            return stmt
        } else {
            let errMsg = String(cString: sqlite3_errmsg(self.db))
            Logger.shared.log(event: "SQL_ERROR", details: "Prepare failed: \(errMsg) | Query: \(query)")
            return nil
        }
    }
    
    public func finalize(stmt: OpaquePointer?) {
        if let stmt = stmt {
            sqlite3_finalize(stmt)
        }
    }
    
    public func testDatabase() -> Bool {
        // 架构级优化：将 COUNT(*) 替换为 LIMIT 1，避免全表扫描导致长达十几秒的阻塞
        let query = "SELECT 1 FROM HanZi LIMIT 1;"
        guard let stmt = prepare(query: query) else { 
            Logger.shared.log(event: "DB_TEST", details: "Failed to prepare test query.")
            return false 
        }
        defer { finalize(stmt: stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            Logger.shared.log(event: "DB_TEST", details: "Database is readable.")
            return true
        }
        Logger.shared.log(event: "DB_TEST", details: "Failed to execute test query or table is empty.")
        return false
    }
    
    public func isSpecialCategory(code: String) -> Bool {
        let query = "SELECT 1 FROM SpecialCategory WHERE Code = ? LIMIT 1;"
        guard let stmt = prepare(query: query) else { return false }
        defer { finalize(stmt: stmt) }
        
        sqlite3_bind_text(stmt, 1, (code as NSString).utf8String, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}