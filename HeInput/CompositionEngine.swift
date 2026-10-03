// CompositionEngine.swift
#if os(macOS)
import Cocoa
import InputMethodKit
#else
import Foundation
#endif
import Combine

public class CompositionEngine {
    public let dataServer: HeDataServer
    public let puncMapper: PunctuationMapper
    public let eventSubject = PassthroughSubject<InputMethodEvent, Never>()
    
    #if os(macOS)
    private let modTracker: ModifierTracker
    private let keyHandler: KeyHandler
    #endif
    
    public var currentState: InputState
    private var promptTimer: Timer?
    
    public var hasNavigated: Bool = false
    
    public var lastUnmanagedChar: Character? = nil
    public var lastCommittedChar: Character? = nil
    
    public var isComposing: Bool {
        return currentState is ComposingState || currentState is AssociationState
    }
    
    public init(dataServer: HeDataServer) {
        self.dataServer = dataServer
        self.puncMapper = PunctuationMapper()
        #if os(macOS)
        self.modTracker = ModifierTracker()
        self.keyHandler = KeyHandler(puncMapper: self.puncMapper)
        #endif
        self.currentState = IdleState()
    }
    
    public func transition(to state: InputState) {
        self.currentState = state
    }
    
    public func showPrompt(_ text: String, duration: TimeInterval = 2.0) {
        self.dataServer.clear()
        self.dataServer.prompt = text
        self.updateUI()
        
        DispatchQueue.main.async {
            self.promptTimer?.invalidate()
            self.promptTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {[weak self] _ in
                guard let self = self else { return }
                if self.dataServer.prompt == text && self.dataServer.getBuffer().isEmpty {
                    self.dataServer.prompt = nil
                    self.updateUI()
                }
            }
        }
    }
    
    #if os(macOS)
    public func handleFlagsChanged(event: NSEvent) -> Bool {
        let toggles = self.modTracker.handleFlagsChanged(event: event)
        let prefs = PreferencesManager.shared
        
        var shouldToggleLang = false
        if prefs.switchLangShortcut == 0 && toggles.toggledLeftShift { shouldToggleLang = true }
        else if prefs.switchLangShortcut == 1 && toggles.toggledRightShift { shouldToggleLang = true }
        else if prefs.switchLangShortcut == 2 && toggles.toggledCtrl { shouldToggleLang = true }
        
        var shouldEnterCommand = false
        if prefs.commandShortcut == 0 && toggles.toggledCtrl { shouldEnterCommand = true }
        else if prefs.commandShortcut == 1 && toggles.toggledRightShift { shouldEnterCommand = true }
        else if prefs.commandShortcut == 2 && toggles.toggledLeftShift { shouldEnterCommand = true }
        
        if shouldToggleLang {
            self.toggleEnglishMode()
            return true
        }
        
        if shouldEnterCommand {
            if PreferencesManager.shared.currentMode != .englishMode {
                self.dataServer.clear()
                self.transition(to: ComposingState())
                self.dataServer.setBuffer("9", mode: PreferencesManager.shared.currentMode)
                self.updateUI()
                return true
            }
        }
        
        return false
    }
    #endif
    
    public func toggleEnglishMode() {
        let prefs = PreferencesManager.shared
        if prefs.currentMode == .englishMode {
            prefs.currentMode = .heMaMode
            if self.isComposing {
                self.dataServer.refreshCandidates(mode: .heMaMode)
                self.updateUI()
            } else {
                self.showPrompt("已切换中文", duration: 2.0)
                self.eventSubject.send(.hideCandidates)
            }
        } else {
            if self.isComposing {
                self.dataServer.cleanupIncompleteNumpadInput()
                self.dataServer.clear()
                self.transition(to: IdleState())
                self.updateUI()
            }
            prefs.currentMode = .englishMode
            self.showPrompt("已切换英文", duration: 2.0)
            self.eventSubject.send(.hideCandidates)
        }
    }
    
    public func toggleSimpTrad() {
        let prefs = PreferencesManager.shared
        prefs.isSimplified.toggle()
        if self.isComposing {
            self.dataServer.refreshCandidates(mode: prefs.currentMode)
            self.updateUI()
        } else {
            self.showPrompt(prefs.isSimplified ? "已切换简体" : "已切换繁体")
        }
    }
    
    public func toggleInputMode() {
        let prefs = PreferencesManager.shared
        if prefs.currentMode == .heMaMode {
            if prefs.enablePinyin {
                prefs.currentMode = .pinYinMode
                if self.isComposing {
                    self.dataServer.refreshCandidates(mode: .pinYinMode)
                    self.updateUI()
                } else {
                    self.showPrompt("已切换拼音")
                }
            }
        } else if prefs.currentMode == .pinYinMode {
            prefs.currentMode = .heMaMode
            if self.isComposing {
                self.dataServer.refreshCandidates(mode: .heMaMode)
                self.updateUI()
            } else {
                self.showPrompt("已切换和码")
            }
        }
    }
    
    public func toggleNumberMode() {
        let prefs = PreferencesManager.shared
        prefs.isNumberMode.toggle()
        if self.isComposing {
            self.dataServer.refreshCandidates(mode: prefs.currentMode)
            self.updateUI()
        } else {
            self.showPrompt(prefs.isNumberMode ? "已切换数字模式" : "已切换字母模式")
        }
    }
    
    public func executeCommand(actionType: CommandActionType) {
        self.dataServer.clear()
        self.transition(to: IdleState())
        
        switch actionType {
        case .openPreferences:
            #if os(macOS)
            PreferencesCoordinator.shared.show()
            #endif
            self.showPrompt("已打开设置")
        case .toggleSimp:
            self.toggleSimpTrad()
        case .toggleMode:
            self.toggleInputMode()
        case .toggleNumber:
            self.toggleNumberMode()
        case .togglePhrase:
            let prefs = PreferencesManager.shared
            prefs.enablePhrase.toggle()
            self.showPrompt(prefs.enablePhrase ? "已开启词组输入" : "已关闭词组输入")
        }
    }
    
    #if os(macOS)
    public func processEvent(event: NSEvent, precedingText: String?) -> Bool {
        self.modTracker.registerOtherKeyPress()
        
        if PreferencesManager.shared.currentMode == .englishMode {
            self.recordUnmanaged(event: event)
            return false
        }
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPreferencesShortcut = flags.contains(.control) && flags.contains(.option) && event.keyCode == 35
        
        if !isPreferencesShortcut && (flags.contains(.command) || flags.contains(.control) || flags.contains(.option)) {
            self.recordUnmanaged(event: event)
            return false
        }
        
        let action = self.keyHandler.parse(event: event)
        return self.processAction(action, precedingText: precedingText)
    }
    
    private func recordUnmanaged(event: NSEvent) {
        if let chars = event.characters, let last = chars.last {
            self.lastUnmanagedChar = last
        }
    }
    #endif
    
    // 架构级优化：抽象出跨平台的事件处理接口，供 iOS 软键盘直接调用
    public func processAction(_ action: KeyAction, precedingText: String?) -> Bool {
        let handled = self.currentState.handle(action: action, engine: self, precedingText: precedingText)
        if handled {
            self.lastUnmanagedChar = nil
        }
        return handled
    }
    
    public func getPrecedingChar(from clientPrecedingText: String?) -> Character? {
        if let text = clientPrecedingText, let last = text.last {
            return last
        }
        if let unmanaged = self.lastUnmanagedChar {
            return unmanaged
        }
        if let committed = self.lastCommittedChar {
            return committed
        }
        return nil
    }
    
    public func commitFirstCandidate() -> Bool {
        return self.commitCandidate(at: 0)
    }
    
    public func commitSelectedCandidate() -> Bool {
        return self.commitCandidate(at: self.dataServer.selectedIndex)
    }
    
    public func commitCandidate(at index: Int) -> Bool {
        let cands = self.dataServer.currentCandidates
        if index >= 0 && index < cands.count {
            let candidate = cands[index]
            
            if candidate.isCategory {
                self.dataServer.setBuffer(candidate.code, mode: PreferencesManager.shared.currentMode)
                self.updateUI()
                return true
            }
            
            if candidate.code.starts(with: "9") && candidate.code.count == 2 {
                if let actionType = CommandTree.shared.getAction(buffer: candidate.code) {
                    self.executeCommand(actionType: actionType)
                } else {
                    let word = candidate.word
                    if PreferencesManager.shared.currentMode != .englishMode {
                        UserDictionaryManager.shared.increaseSystemWordWeight(word: word)
                    }
                    self.dataServer.clear()
                    self.transition(to: IdleState())
                    self.commitText(word)
                }
                return true
            }
            
            let word = candidate.word
            
            if PreferencesManager.shared.currentMode != .englishMode {
                UserDictionaryManager.shared.increaseSystemWordWeight(word: word)
            }
            
            self.dataServer.clear()
            self.commitText(word)
            
            if PreferencesManager.shared.currentMode != .englishMode && PreferencesManager.shared.enablePhrase {
                self.dataServer.setAssociation(word: word)
                if !self.dataServer.allCandidates.isEmpty {
                    self.transition(to: AssociationState())
                    self.updateUI()
                } else {
                    self.transition(to: IdleState())
                }
            } else {
                self.transition(to: IdleState())
            }
            
            return true
        }
        return false
    }
    
    public func forceCommit() {
        if !self.dataServer.getBuffer().isEmpty {
            let raw = self.dataServer.getBuffer()
            self.dataServer.clear()
            self.transition(to: IdleState())
            self.commitText(raw)
        }
    }
    
    public func commitText(_ text: String) {
        Logger.shared.log(event: "COMMIT", details: "Text: \(text)")
        if let last = text.last {
            self.lastCommittedChar = last
        }
        
        StatisticsManager.shared.recordWords(text.count)
        
        self.eventSubject.send(.commitText(text))
    }
    
    public func updateUI() {
        let buffer = self.dataServer.getBuffer()
        let prompt = self.dataServer.prompt
        let cands = self.dataServer.currentCandidates
        
        if buffer.isEmpty && prompt == nil && cands.isEmpty {
            self.eventSubject.send(.hideCandidates)
        } else {
            let selectedIndex = self.dataServer.selectedIndex
            var reverseLookupText: String? = nil
            
            if selectedIndex >= 0 && selectedIndex < cands.count {
                let candidate = cands[selectedIndex]
                reverseLookupText = self.dataServer.getReverseLookupText(for: candidate, mode: PreferencesManager.shared.currentMode)
            }
            
            self.eventSubject.send(.updateMarkedText(buffer, cands, selectedIndex, prompt, reverseLookupText))
        }
    }
}