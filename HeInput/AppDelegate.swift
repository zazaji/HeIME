// AppDelegate.swift
#if os(macOS)
import Cocoa
import InputMethodKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer
    
    init(server: IMKServer) {
        self.server = server
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        Logger.shared.log(event: "APP", details: "Application did finish launching.")
        
        if InputMethodHelper.isSandboxed() {
            Logger.shared.log(event: "SANDBOX_ERROR", details: "App is running in Sandbox. Input Methods cannot be sandboxed.")
            let alert = NSAlert()
            alert.messageText = "架构配置错误：沙盒已开启"
            alert.informativeText = "macOS 输入法不能在 App Sandbox 环境下运行，否则无法注册到系统且无法访问真实的 /Library 目录。\n\n请在 Xcode 的 Target -> Signing & Capabilities 中删除 'App Sandbox'，然后重新编译。"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        
        if Bundle.main.path(forResource: "HeMa", ofType: "db") == nil {
            Logger.shared.log(event: "MISSING_RESOURCE", details: "HeMa.db is missing!")
            let alert = NSAlert()
            alert.messageText = "数据库丢失"
            alert.informativeText = "HeMa.db 未包含在应用中，请重新安装。"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        if Bundle.main.path(forResource: "he_icon", ofType: "png") == nil {
            Logger.shared.log(event: "MISSING_RESOURCE", details: "he_icon.png is missing from the bundle!")
        }
        
        if !InputMethodHelper.checkBundleIdentifier() {
            NSApp.terminate(nil)
            return
        }
        
        if InputMethodHelper.installAndRelaunchIfNeeded() {
            Logger.shared.log(event: "APP", details: "App is relaunching from standard Input Methods directory.")
            return
        }
        
        InputSourceManager.setupInputSource()
        
        _ = SharedDataManager.shared
        
        let forceShowUI = CommandLine.arguments.contains("--show-ui")
        let isEnabled = InputMethodHelper.isInputMethodEnabled()
        
        if forceShowUI || !isEnabled {
            Logger.shared.log(event: "APP", details: "Showing setup window. Force: \(forceShowUI), Enabled: \(isEnabled)")
            PreferencesCoordinator.shared.show()
        } else {
            Logger.shared.log(event: "APP", details: "Input method is enabled and no force flag. Running in background.")
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.log(event: "APP", details: "Application will terminate.")
    }
}
#endif