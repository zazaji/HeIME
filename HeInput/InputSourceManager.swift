// InputSourceManager.swift
#if os(macOS)
import Foundation
import Carbon
import Cocoa

public class InputSourceManager {
    
    public static func setupInputSource() {
        let bundleURL = Bundle.main.bundleURL
        let bundleID = Bundle.main.bundleIdentifier ?? "hezi.inputmethod.HeInput"

        #if DEBUG
        // 架构级优化：调试构建避免每次启动都执行耗时的 lsregister，向系统注册表反复写入
        if !self.needsRegistration(bundleID: bundleID) {
            Logger.shared.log(event: "INPUT_SOURCE", details: "Already registered for this version and path. Skipping lsregister.")
            self.cleanupAndEnable(bundleID: bundleID)
            return
        }
        #endif

        // 正式版每次启动都刷新注册：升级时可能以相同版本号原地替换文件，
        // 只比较“路径+版本”会跳过注册，系统输入源缓存指向旧文件导致输入法失效
        Logger.shared.log(event: "INPUT_SOURCE", details: "Setting up input source for \(bundleID)")

        self.runLSRegister(appURL: bundleURL, unregister: false)

        var status: OSStatus = -1
        for attempt in 1...3 {
            status = TISRegisterInputSource(bundleURL as CFURL)
            Logger.shared.log(event: "REGISTER", details: "Attempt \(attempt): TISRegisterInputSource status: \(status)")
            if status == noErr { break }
            Thread.sleep(forTimeInterval: 0.5)
        }

        self.cleanupAndEnable(bundleID: bundleID)
    }
    
    private static func needsRegistration(bundleID: String) -> Bool {
        let defaults = UserDefaults.standard
        let currentPath = Bundle.main.bundleURL.path
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let versionString = "\(currentVersion).\(currentBuild)"
        
        let lastPath = defaults.string(forKey: "HeInput_LastRegisteredPath")
        let lastVersion = defaults.string(forKey: "HeInput_LastRegisteredVersion")
        
        // 如果路径或版本发生变化，需要重新注册
        if currentPath != lastPath || versionString != lastVersion {
            defaults.set(currentPath, forKey: "HeInput_LastRegisteredPath")
            defaults.set(versionString, forKey: "HeInput_LastRegisteredVersion")
            return true
        }
        
        // 检查系统列表中是否真实存在该输入法，防止用户在系统设置中手动删除
        let properties: CFDictionary? = nil
        guard let sources = TISCreateInputSourceList(properties, true) else { return true }
        let sourceList = sources.takeRetainedValue() as? [TISInputSource] ?? []
        for source in sourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if id.hasPrefix(bundleID) {
                    return false
                }
            }
        }
        
        return true
    }
    
    public static func cleanupAndEnable(bundleID: String) {
        let myPath = Bundle.main.bundleURL.path
        let userInputMethodsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Input Methods").path ?? ""
        let systemInputMethodsDir = FileManager.default.urls(for: .libraryDirectory, in: .localDomainMask).first?
            .appendingPathComponent("Input Methods").path ?? ""
        let isInstalledRun = myPath.hasPrefix(userInputMethodsDir) || myPath.hasPrefix(systemInputMethodsDir)

        let properties: CFDictionary? = nil
        guard let sources = TISCreateInputSourceList(properties, true) else {
            Logger.shared.log(event: "CLEANUP", details: "Failed to get input source list.")
            return
        }

        let sourceList = sources.takeRetainedValue() as?[TISInputSource] ?? []

        var matchingSources: [(path: String?, source: TISInputSource)] = []
        for source in sourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if id.hasPrefix(bundleID) {
                    var path: String? = nil
                    // "TISPropertyBundlePath" 非公开常量，但属性表里存在；取不到时走末位回退
                    if let pathPtr = TISGetInputSourceProperty(source, "TISPropertyBundlePath" as CFString) {
                        path = Unmanaged<CFString>.fromOpaque(pathPtr).takeUnretainedValue() as String
                    }
                    matchingSources.append((path, source))
                }
            }
        }

        Logger.shared.log(event: "CLEANUP", details: "Found \(matchingSources.count) input sources matching prefix \(bundleID), installed run: \(isInstalledRun)")

        if matchingSources.isEmpty { return }

        // 优先启用与当前进程路径一致的输入源；历史调试构建和已删除路径的残留注册按需停用
        let currentIndex = matchingSources.firstIndex { $0.path == myPath }
            ?? matchingSources.count - 1

        for (index, item) in matchingSources.enumerated() {
            if index == currentIndex {
                let enableStatus = TISEnableInputSource(item.source)
                Logger.shared.log(event: "ENABLE", details: "Enabled input source at \(item.path ?? "unknown"), status: \(enableStatus)")
            } else if isInstalledRun {
                // 只有正式安装版运行时才清理同 Bundle ID 的其它注册（含调试构建残留），
                // 调试运行不动系统里已启用的正式输入法
                let disableStatus = TISDisableInputSource(item.source)
                Logger.shared.log(event: "CLEANUP", details: "Disabled stale input source at \(item.path ?? "unknown"), status: \(disableStatus)")
            }
        }
    }
    
    public static func deepClean() {
        let bundleID = Bundle.main.bundleIdentifier ?? "hezi.inputmethod.HeInput"
        Logger.shared.log(event: "DEEP_CLEAN", details: "Starting deep clean for \(bundleID)")
        
        let properties: CFDictionary? = nil
        guard let sources = TISCreateInputSourceList(properties, true) else { return }
        let sourceList = sources.takeRetainedValue() as?[TISInputSource] ?? []
        
        var targetSources: [(String, TISInputSource)] = []
        
        for source in sourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if id.hasPrefix(bundleID) || id.lowercased().contains("hezi") || id.lowercased().contains("heinput") {
                    targetSources.append((id, source))
                }
            }
        }
        
        Logger.shared.log(event: "DEEP_CLEAN", details: "Found \(targetSources.count) related input sources to clean.")
        
        for (id, source) in targetSources {
            let status = TISDisableInputSource(source)
            Logger.shared.log(event: "DEEP_CLEAN", details: "Disabled \(id), status: \(status)")
        }
        
        // 强制重置注册状态
        UserDefaults.standard.removeObject(forKey: "HeInput_LastRegisteredPath")
        UserDefaults.standard.removeObject(forKey: "HeInput_LastRegisteredVersion")
        
        self.setupInputSource()
        
        Logger.shared.log(event: "DEEP_CLEAN", details: "Deep clean finished. Recommend restarting HIToolbox.")
    }
    
    public static func runLSRegister(appURL: URL, unregister: Bool) {
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        let process = Process()
        if #available(macOS 14.6, *) {
            process.executableURL = URL(fileURLWithPath: lsregisterPath)
        } else {
            process.launchPath = lsregisterPath
        }
        
        if unregister {
            process.arguments = ["-u", appURL.path]
        } else {
            process.arguments = ["-f", "-r", appURL.path]
        }
        
        do {
            if #available(macOS 14.6, *) {
                try process.run()
            } else {
                process.launch()
            }
            process.waitUntilExit()
            Logger.shared.log(event: "LSREGISTER", details: "Successfully \(unregister ? "unregistered" : "registered") \(appURL.path)")
        } catch {
            Logger.shared.log(event: "LSREGISTER_ERROR", details: error.localizedDescription)
        }
    }
    
    public static func restartHIToolbox() {
        let process = Process()
        process.launchPath = "/usr/bin/killall"
        process.arguments = ["-9", "HIToolbox"]
        do {
            try process.run()
            Logger.shared.log(event: "RESTART_SERVICE", details: "HIToolbox killed. System will auto-restart it.")
        } catch {
            Logger.shared.log(event: "RESTART_SERVICE_ERROR", details: error.localizedDescription)
        }
    }
}
#endif