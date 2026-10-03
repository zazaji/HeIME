// MenuManager.swift
#if os(macOS)
import Cocoa
import InputMethodKit

public class MenuManager {
    public static let shared = MenuManager()
    
    private init() {}
    
    public func buildMenu() -> NSMenu {
        let menu = NSMenu(title: NSLocalizedString("menu.title", comment: "Menu title"))
        let prefs = PreferencesManager.shared
        
        if prefs.enablePinyin {
            let modeTitle = prefs.currentMode == .heMaMode ? "当前: 和码" : "当前: 拼音"
            let modeItem = NSMenuItem(title: modeTitle, action: #selector(self.toggleMode), keyEquivalent: "")
            modeItem.target = self
            menu.addItem(modeItem)
        } else {
            let modeItem = NSMenuItem(title: "当前: 和码", action: nil, keyEquivalent: "")
            modeItem.isEnabled = false
            menu.addItem(modeItem)
        }
        
        let engTitle = prefs.currentMode == .englishMode ? "当前: 英文 (按左Shift切换)" : "当前: 中文 (按左Shift切换)"
        let engItem = NSMenuItem(title: engTitle, action: #selector(self.toggleEng), keyEquivalent: "")
        engItem.target = self
        menu.addItem(engItem)
        
        let simpItem = NSMenuItem(title: prefs.isSimplified ? "当前: 简体" : "当前: 繁体", action: #selector(self.toggleSimp), keyEquivalent: "")
        simpItem.target = self
        menu.addItem(simpItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let prefItem = NSMenuItem(title: "偏好设置...", action: #selector(self.openPref), keyEquivalent: "P")
        prefItem.target = self
        prefItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(prefItem)
        
        return menu
    }
    
    @objc private func toggleMode() {
        let prefs = PreferencesManager.shared
        if prefs.enablePinyin {
            prefs.currentMode = (prefs.currentMode == .heMaMode) ? .pinYinMode : .heMaMode
        }
    }
    
    @objc private func toggleEng() {
        let prefs = PreferencesManager.shared
        prefs.currentMode = (prefs.currentMode == .englishMode) ? .heMaMode : .englishMode
    }
    
    @objc private func toggleSimp() {
        let prefs = PreferencesManager.shared
        prefs.isSimplified.toggle()
    }
    
    @objc private func openPref() {
        Logger.shared.log(event: "MENU", details: "Open Preferences triggered from menu")
        PreferencesCoordinator.shared.show()
    }
}
#endif