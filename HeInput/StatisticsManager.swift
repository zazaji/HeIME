// StatisticsManager.swift
import Foundation
import Network

public class StatisticsManager {
    public static let shared = StatisticsManager()

    // 上报端点不写入源码（避免泄漏）：从 App Group UserDefaults 读取，
    // 键名 HeInput_ReportEndpoint；未配置时本地计数照常累计，网络上报自动停用。
    private var endpoint: String? {
        AppConstants.sharedUserDefaults.string(forKey: "HeInput_ReportEndpoint")
    }
    // 架构级优化：使用 App Group 共享的 UserDefaults
    private let defaults = AppConstants.sharedUserDefaults
    
    private let deviceIdKey = "HeInput_DeviceID"
    private let unreportedCountKey = "HeInput_UnreportedWordCount"
    private let lastReportDateKey = "HeInput_LastReportDate"
    private let lastAttemptTimeKey = "HeInput_LastAttemptTime"
    
    private var isReporting = false
    private let queue = DispatchQueue(label: "hezi.inputmethod.statistics")
    
    private let monitor = NWPathMonitor()
    private var isNetworkAvailable = false
    
    public var deviceId: String {
        if let id = defaults.string(forKey: deviceIdKey) {
            return id
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: deviceIdKey)
            return newId
        }
    }
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = path.status == .satisfied
            if path.status == .satisfied {
                self?.reportIfNeeded(checkInterval: true)
            }
        }
        let monitorQueue = DispatchQueue(label: "hezi.inputmethod.networkmonitor")
        monitor.start(queue: monitorQueue)
    }
    
    public func recordWords(_ count: Int) {
        queue.async {
            let currentCount = self.defaults.integer(forKey: self.unreportedCountKey)
            self.defaults.set(currentCount + count, forKey: self.unreportedCountKey)
            
            let today = self.getTodayString()
            let lastDate = self.defaults.string(forKey: self.lastReportDateKey) ?? today
            
            if lastDate != today {
                self.report()
            } else if currentCount + count >= 50 {
                self.report()
            }
        }
    }
    
    public func reportIfNeeded(checkInterval: Bool = false) {
        queue.async {
            let currentCount = self.defaults.integer(forKey: self.unreportedCountKey)
            if currentCount > 0 {
                if checkInterval {
                    let lastAttempt = self.defaults.double(forKey: self.lastAttemptTimeKey)
                    let now = Date().timeIntervalSince1970
                    if now - lastAttempt >= 300 {
                        self.report()
                    }
                } else {
                    self.report()
                }
            }
        }
    }
    
    private func report() {
        guard !isReporting else { return }
        guard isNetworkAvailable else {
            Logger.shared.log(event: "STAT_SKIP", details: "Network unavailable, skip reporting.")
            return
        }
        
        let countToReport = defaults.integer(forKey: unreportedCountKey)
        guard countToReport > 0 else { return }

        // 端点未配置：跳过上报（不置 isReporting，本地累计保留）
        guard let endpoint = self.endpoint, !endpoint.isEmpty, let url = URL(string: endpoint) else {
            Logger.shared.log(event: "STAT_DISABLED", details: "Report endpoint not configured, skip reporting.")
            return
        }

        isReporting = true
        defaults.set(Date().timeIntervalSince1970, forKey: lastAttemptTimeKey)

        let today = getTodayString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "deviceId": deviceId,
            "date": today,
            "wordCount": countToReport
        ]
        
        do {
            let payloadData = try JSONSerialization.data(withJSONObject: payload, options:[])
            request.httpBody = payloadData
            
            if let bodyString = String(data: payloadData, encoding: .utf8) {
                Logger.shared.log(event: "STAT_REQ", details: "URL: \(url.absoluteString), Headers: \(request.allHTTPHeaderFields ?? [:]), Body: \(bodyString)")
            }
        } catch {
            Logger.shared.log(event: "STAT_ERROR", details: "Failed to serialize payload")
            isReporting = false
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) {[weak self] data, response, error in
            guard let self = self else { return }
            
            self.queue.async {
                self.isReporting = false
                
                if let error = error {
                    Logger.shared.log(event: "STAT_ERROR", details: "Report failed: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    let responseBody = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    Logger.shared.log(event: "STAT_RES", details: "Status: \(httpResponse.statusCode), Body: \(responseBody)")
                    
                    if (200...299).contains(httpResponse.statusCode) {
                        let currentCount = self.defaults.integer(forKey: self.unreportedCountKey)
                        self.defaults.set(max(0, currentCount - countToReport), forKey: self.unreportedCountKey)
                        self.defaults.set(today, forKey: self.lastReportDateKey)
                        Logger.shared.log(event: "STAT_SUCCESS", details: "Successfully reported \(countToReport) words.")
                    }
                }
            }
        }
        task.resume()
    }
    
    private func getTodayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current
        return formatter.string(from: Date())
    }
}