// Logger.swift
import Foundation

public class Logger {
    public static let shared = Logger()
    
    private let formatter: DateFormatter
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "hezi.inputmethod.logger")
    
    private init() {
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // 架构级优化：优先使用 App Group 共享目录，确保 iOS 扩展和主 App 都能读写日志
        let logsDir: URL
        if let sharedURL = AppConstants.sharedContainerURL {
            logsDir = sharedURL.appendingPathComponent("Logs")
        } else {
            logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Logs")
        }
        
        self.logFileURL = logsDir.appendingPathComponent("HeInput.log")
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }
    
    public func log(event: String, details: String) {
        let time = self.formatter.string(from: Date())
        let msg = "[\(time)][\(event)] \(details)"
        print(msg)
        
        NSLog(msg)
        
        queue.sync {
            if let data = (msg + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }
    }
    
    public func logInputCharacter(_ char: String, mode: InputMode) {
        let time = self.formatter.string(from: Date())
        let msg = "[\(time)][INPUT_CHAR] Character: '\(char)', Mode: \(mode)"
        print(msg)
        NSLog(msg)
        
        queue.sync {
            if let data = (msg + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }
    }
    
    public func logConversion(input: String, candidates: [CandidateItem], selected: String?) {
        let time = self.formatter.string(from: Date())
        let candidateStr = candidates.map { "\($0.word)(\($0.code))" }.joined(separator: ", ")
        let selectedStr = selected ?? "none"
        let msg = "[\(time)][CONVERSION] Input: '\(input)', Candidates: [\(candidateStr)], Selected: '\(selectedStr)'"
        print(msg)
        NSLog(msg)
        
        queue.sync {
            if let data = (msg + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }
    }
    
    public func logError(error: Error, context: String) {
        self.log(event: "ERROR", details: "Context: \(context) | Error: \(error.localizedDescription)")
    }
}