// PreferencesManager.swift
import Foundation
import Combine

extension Notification.Name {
    public static let heInputPreferencesChanged = Notification.Name("heInputPreferencesChanged")
}

public class PreferencesManager: ObservableObject {
    public static let shared = PreferencesManager()
    
    // 架构级优化：使用 App Group 共享的 UserDefaults，确保 iOS 主 App 和 Extension 设置同步
    private let defaults = AppConstants.sharedUserDefaults
    
    @Published public var currentModeRaw: Int {
        didSet { 
            defaults.set(currentModeRaw, forKey: "HeInput_CurrentMode") 
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    @Published public var isSimplified: Bool {
        didSet { 
            defaults.set(isSimplified, forKey: "HeInput_IsSimplified") 
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    @Published public var pageSize: Int {
        didSet { 
            defaults.set(pageSize, forKey: "HeInput_PageSize") 
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    @Published public var enablePhrase: Bool {
        didSet { 
            defaults.set(enablePhrase, forKey: "HeInput_EnablePhrase") 
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    @Published public var enablePinyin: Bool {
        didSet { 
            defaults.set(enablePinyin, forKey: "HeInput_EnablePinyin") 
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    @Published public var isNumberMode: Bool {
        didSet { 
            defaults.set(isNumberMode, forKey: "HeInput_IsNumberMode") 
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    @Published public var switchLangShortcut: Int {
        didSet {
            defaults.set(switchLangShortcut, forKey: "HeInput_SwitchLangShortcut")
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    @Published public var commandShortcut: Int {
        didSet {
            defaults.set(commandShortcut, forKey: "HeInput_CommandShortcut")
            defaults.synchronize()
            NotificationCenter.default.post(name: .heInputPreferencesChanged, object: nil)
        }
    }
    
    private init() {
        self.currentModeRaw = defaults.object(forKey: "HeInput_CurrentMode") as? Int ?? InputMode.heMaMode.rawValue
        self.isSimplified = defaults.object(forKey: "HeInput_IsSimplified") as? Bool ?? true
        self.pageSize = defaults.object(forKey: "HeInput_PageSize") as? Int ?? 5
        self.enablePhrase = defaults.object(forKey: "HeInput_EnablePhrase") as? Bool ?? true
        self.enablePinyin = defaults.object(forKey: "HeInput_EnablePinyin") as? Bool ?? true
        self.isNumberMode = defaults.object(forKey: "HeInput_IsNumberMode") as? Bool ?? false
        
        self.switchLangShortcut = defaults.object(forKey: "HeInput_SwitchLangShortcut") as? Int ?? 0
        self.commandShortcut = defaults.object(forKey: "HeInput_CommandShortcut") as? Int ?? 0
    }
    
    public var currentMode: InputMode {
        get { InputMode(rawValue: currentModeRaw) ?? .heMaMode }
        set { 
            currentModeRaw = newValue.rawValue 
            Logger.shared.log(event: "PREF", details: "Mode set to \(newValue)")
        }
    }
}