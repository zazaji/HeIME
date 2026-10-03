// HeInputController.swift
#if os(macOS)
import Cocoa
import InputMethodKit
import Combine

@objc(HeInputController)
public class HeInputController: IMKInputController {
    
    private var engine: CompositionEngine!
    private static let notFoundRange = NSRange(location: NSNotFound, length: NSNotFound)
    private var cancellables: Set<AnyCancellable> = []
    
    private func getCurrentAppBundleId() -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if app.isActive {
                return app.bundleIdentifier
            }
        }
        return nil
    }
    
    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        
        let dataServer = HeDataServer()
        self.engine = CompositionEngine(dataServer: dataServer)
        
        self.engine.eventSubject.sink {[weak self] event in
            self?.handleEngineEvent(event)
        }.store(in: &cancellables)
        
        Logger.shared.log(event: "INIT", details: "Controller initialized.")
    }
    
    private func handleEngineEvent(_ event: InputMethodEvent) {
        guard let client = self.client() else { 
            Logger.shared.log(event: "ENGINE_EVENT", details: "Failed to get client.")
            return 
        }
        
        switch event {
        case .commitText(let text):
            Logger.shared.log(event: "DEBUG_COMMIT", details: "Committing text: '\(text)'")
            client.insertText(text, replacementRange: Self.notFoundRange)
            CandidatesWindow.shared.hide()
            
        case .updateMarkedText(let buffer, let candidates, let selectedIndex, let prompt, let reverseLookupText):
            Logger.shared.log(event: "DEBUG_INPUT", details: "Buffer: '\(buffer)', Prompt: '\(prompt ?? "nil")'")
            
            if buffer.isEmpty {
                let attrString = NSAttributedString(string: "", attributes: [:])
                client.setMarkedText(
                    attrString,
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: Self.notFoundRange
                )
            } else {
                let currentAppBundleId = getCurrentAppBundleId()
                
                if currentAppBundleId?.contains("com.tencent") == true || 
                   currentAppBundleId?.contains("wechat") == true ||
                   currentAppBundleId?.contains("WeChat") == true {
                    let invisibleText = "\u{200B}"
                    let attrString = NSAttributedString(string: invisibleText, attributes:[
                        .foregroundColor: NSColor.clear,
                        .font: NSFont.systemFont(ofSize: 0.1)
                    ])
                    client.setMarkedText(
                        attrString,
                        selectionRange: NSRange(location: invisibleText.utf16.count, length: 0),
                        replacementRange: Self.notFoundRange
                    )
                }
            }

            var cursorRect = NSRect.zero
            _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &cursorRect)

            if cursorRect == .zero {
                if let screen = NSScreen.main {
                    cursorRect = NSRect(
                        x: screen.visibleFrame.midX - 100,
                        y: screen.visibleFrame.midY - 50,
                        width: 0,
                        height: 20
                    )
                }
            }

            CandidatesWindow.shared.update(
                buffer: buffer,
                candidates: candidates,
                selectedIndex: selectedIndex,
                prompt: prompt,
                reverseLookupText: reverseLookupText,
                cursorRect: cursorRect
            ) {[weak self] action in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch action {
                    case .select(let index):
                        _ = self.engine.commitCandidate(at: index)
                    case .toggleMode:
                        self.engine.toggleInputMode()
                    case .toggleSimp:
                        self.engine.toggleSimpTrad()
                    case .toggleEng:
                        self.engine.toggleEnglishMode()
                    case .toggleNumberMode:
                        self.engine.toggleNumberMode()
                    case .openPreferences:
                        PreferencesCoordinator.shared.show()
                    }
                }
            }
            
        case .hideCandidates:
            Logger.shared.log(event: "DEBUG_HIDE", details: "Hiding candidates and clearing marked text")
            let attrString = NSAttributedString(string: "", attributes: [:])
            client.setMarkedText(
                attrString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: Self.notFoundRange
            )
            CandidatesWindow.shared.hide()
        }
    }
    
    public override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Logger.shared.log(event: "ACTIVATE", details: "Server activated.")
        self.engine.dataServer.clear()
        self.engine.transition(to: IdleState())
    }
    
    public override func deactivateServer(_ sender: Any!) {
        if self.engine.isComposing {
            self.engine.dataServer.cleanupIncompleteNumpadInput()
            self.engine.dataServer.clear()
            self.engine.transition(to: IdleState())
            
            if let client = self.client() {
                let attrString = NSAttributedString(string: "", attributes: [:])
                client.setMarkedText(
                    attrString,
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: Self.notFoundRange
                )
            }
        }
        CandidatesWindow.shared.hide()
        
        StatisticsManager.shared.reportIfNeeded()
        
        super.deactivateServer(sender)
        Logger.shared.log(event: "DEACTIVATE", details: "Server deactivated.")
    }
    
    public override func recognizedEvents(_ sender: Any!) -> Int {
        let flags = NSEvent.EventTypeMask.flagsChanged.rawValue
        let keyDown = NSEvent.EventTypeMask.keyDown.rawValue
        let keyUp = NSEvent.EventTypeMask.keyUp.rawValue
        return Int(flags | keyDown | keyUp)
    }
    
    public override func menu() -> NSMenu! {
        return MenuManager.shared.buildMenu()
    }
    
    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        
        let client = sender as? IMKTextInput
        if client == nil {
            Logger.shared.log(event: "KEY_EVENT", details: "Warning: sender is not IMKTextInput")
        }
        
        Logger.shared.log(
            event: "KEY_EVENT", 
            details: "Type: \(event.type.rawValue), KeyCode: \(event.keyCode), Flags: \(event.modifierFlags.rawValue)"
        )
        
        if event.type == .flagsChanged {
            let handled = self.engine.handleFlagsChanged(event: event)
            Logger.shared.log(event: "KEY_EVENT", details: "FlagsChanged handled: \(handled)")
            return handled
        }
        
        if event.type == .keyUp {
            if self.engine.isComposing {
                let keyCode = event.keyCode
                if keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126 || keyCode == 116 || keyCode == 121 {
                    return true
                }
            }
            return false
        }
        
        if event.type != .keyDown {
            return false
        }
        
        var precedingText: String? = nil
        if let client = client {
            let range = client.selectedRange()
            if range.location != NSNotFound && range.location > 0 {
                let preRange = NSRange(location: range.location - 1, length: 1)
                if let attrStr = client.attributedSubstring(from: preRange) {
                    precedingText = attrStr.string
                }
            }
        }
        
        let handled = self.engine.processEvent(event: event, precedingText: precedingText)
        Logger.shared.log(event: "KEY_EVENT", details: "KeyDown handled: \(handled)")
        
        if !handled && self.engine.isComposing {
            self.engine.forceCommit()
        }
        
        return handled
    }
}
#endif