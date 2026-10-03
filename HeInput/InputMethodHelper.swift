// InputMethodHelper.swift
#if os(macOS)
import Foundation
import Carbon
import Cocoa

public class InputMethodHelper {
    
    public static func isSandboxed() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
    
    public static func ensureSystemDirectoriesExist() {
        guard let libraryDir = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else { return }
        
        let inputMethodsDir = libraryDir.appendingPathComponent("Input Methods")
        let keyboardLayoutsDir = libraryDir.appendingPathComponent("Keyboard Layouts")
        
        for dir in [inputMethodsDir, keyboardLayoutsDir] {
            if !FileManager.default.fileExists(atPath: dir.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: dir,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    Logger.shared.log(
                        event: "DIR_CREATE",
                        details: "Created directory: \(dir.path)"
                    )
                } catch {
                    Logger.shared.log(
                        event: "DIR_ERROR",
                        details: "Failed to create \(dir.path): \(error)"
                    )
                }
            }
        }
    }
    
    public static func checkBundleIdentifier() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        
        if !bundleID.contains(".inputmethod.") {
            let alert = NSAlert()
            alert.messageText = "Bundle Identifier 配置错误"
            alert.informativeText = "macOS 强制要求第三方输入法的 Bundle Identifier " +
                                    "必须包含 '.inputmethod.' 关键字。\n\n" +
                                    "当前为: \(bundleID)\n\n" +
                                    "请在 Xcode 的 Target -> General 中修改 " +
                                    "Bundle Identifier，然后重新编译运行。"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "退出")
            alert.runModal()
            return false
        }
        return true
    }
    
    public static func installAndRelaunchIfNeeded() -> Bool {
        #if DEBUG
        // 调试构建保留在 DerivedData 运行，不替换已安装的正式版。
        // 每次重建的签名 cdhash 都不同，覆盖安装会让系统把输入法视为“被修改的应用”，
        // 导致每次启动都重新弹出授权确认。
        Logger.shared.log(event: "ENV_CHECK", details: "Debug build: skip self-install, keep running from build directory.")
        return false
        #else
        return self.installAndRelaunchIfNeededRelease()
        #endif
    }

    private static func installAndRelaunchIfNeededRelease() -> Bool {
        self.ensureSystemDirectoriesExist()
        
        let bundleURL = Bundle.main.bundleURL
        
        let userLibraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let systemLibraryDir = FileManager.default.urls(for: .libraryDirectory, in: .localDomainMask).first
        
        let userInputMethodsDir = userLibraryDir?.appendingPathComponent("Input Methods")
        let systemInputMethodsDir = systemLibraryDir?.appendingPathComponent("Input Methods")
        
        if let userDir = userInputMethodsDir, bundleURL.path.hasPrefix(userDir.path) {
            Logger.shared.log(event: "ENV_CHECK", details: "App is running from User Input Methods directory.")
            return false
        }
        
        if let sysDir = systemInputMethodsDir, bundleURL.path.hasPrefix(sysDir.path) {
            Logger.shared.log(event: "ENV_CHECK", details: "App is running from System Input Methods directory.")
            return false
        }
        
        Logger.shared.log(
            event: "ENV_CHECK",
            details: "App running from invalid directory. Copying to User Input Methods."
        )
        
        guard let targetDir = userInputMethodsDir else { return false }
        let destinationURL = targetDir.appendingPathComponent(bundleURL.lastPathComponent)
        
        do {
            // 先结束正在运行的旧实例：LaunchServices 按 Bundle ID 去重，
            // 旧进程还活着时 openApplication 只会激活旧进程，新副本永远不会启动注册
            self.terminateOtherInstances()

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
                Logger.shared.log(
                    event: "INSTALL",
                    details: "Removed old version at \(destinationURL.path)"
                )
            }

            try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
            Logger.shared.log(
                event: "INSTALL",
                details: "Successfully copied app to \(destinationURL.path)"
            )

            // 清除隔离属性，避免 Gatekeeper 对复制出来的副本反复要求确认
            self.clearQuarantine(at: destinationURL)

            let launched = self.launchNewInstance(at: destinationURL)
            if launched {
                Logger.shared.log(
                    event: "RELAUNCH",
                    details: "Launched new instance. Terminating current."
                )
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
                return true
            } else {
                Logger.shared.log(event: "RELAUNCH_ERROR", details: "open -n failed; continuing with current process.")
                return false
            }

        } catch {
            Logger.shared.log(
                event: "INSTALL_ERROR",
                details: "Failed to install: \(error.localizedDescription)"
            )
            return false
        }
    }

    /// 结束除自身外的所有 HeInput 进程，释放 IMKServer 的 Mach 连接名
    private static func terminateOtherInstances() {
        let pipe = Pipe()
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "HeInput"]
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        do {
            try pgrep.run()
        } catch {
            Logger.shared.log(event: "INSTALL", details: "pgrep failed: \(error.localizedDescription)")
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()

        let myPID = ProcessInfo.processInfo.processIdentifier
        let lines = String(data: data, encoding: .utf8)?
            .split(whereSeparator: \.isNewline) ?? []

        for line in lines {
            guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)) else { continue }
            guard pid != myPID else { continue }
            kill(pid, SIGTERM)
            Logger.shared.log(event: "INSTALL", details: "Terminated old instance pid \(pid).")
        }

        if !lines.isEmpty {
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private static func clearQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-cr", url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Logger.shared.log(event: "INSTALL", details: "xattr failed: \(error.localizedDescription)")
        }
    }

    /// 用 open -n 强制启动新实例，绕过 LaunchServices 按 Bundle ID 的去重
    private static func launchNewInstance(at url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", url.path, "--args", "--show-ui"]
        do {
            try process.run()
            process.waitUntilExit()
            let success = process.terminationStatus == 0
            Logger.shared.log(event: "RELAUNCH", details: "open -n exited with status \(process.terminationStatus).")
            return success
        } catch {
            Logger.shared.log(event: "RELAUNCH_ERROR", details: error.localizedDescription)
            return false
        }
    }

    public static func isInputMethodEnabled() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        
        let properties: CFDictionary? = nil
        guard let sources = TISCreateInputSourceList(properties, true) else {
            Logger.shared.log(
                event: "STATUS_CHECK",
                details: "TISCreateInputSourceList returned nil."
            )
            return false
        }
        
        let sourceList = sources.takeRetainedValue() as? [TISInputSource] ?? []
        
        for source in sourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if id.hasPrefix(bundleID) {
                    if let enablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                        let isEnabled = Unmanaged<CFBoolean>.fromOpaque(enablePtr).takeUnretainedValue()
                        if CFBooleanGetValue(isEnabled) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }
    
    public static func openKeyboardPreferences() {
        let urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            Logger.shared.log(event: "SYSTEM_PREF", details: "Opened keyboard preferences.")
        } else {
            Logger.shared.log(event: "SYSTEM_PREF_ERROR", details: "Failed to create URL for keyboard preferences.")
        }
    }
}
#endif