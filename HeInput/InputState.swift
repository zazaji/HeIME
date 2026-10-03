// InputState.swift
#if os(macOS)
import Cocoa
#else
import Foundation
#endif

public protocol InputState {
    func handle(action: KeyAction, engine: CompositionEngine, precedingText: String?) -> Bool
}

public class IdleState: InputState {
    public func handle(action: KeyAction, engine: CompositionEngine, precedingText: String?) -> Bool {
        let mode = PreferencesManager.shared.currentMode
        engine.hasNavigated = false
        
        switch action {
        case .char(let c):
            if mode == .heMaMode && PreferencesManager.shared.isNumberMode {
                let validChars = "123450"
                if !validChars.contains(c) {
                    return false
                }
            }
            Logger.shared.logInputCharacter(c, mode: mode)
            engine.dataServer.appendCode(c, mode: mode)
            engine.transition(to: ComposingState())
            engine.updateUI()
            return true
            
        case .numpadChar(let c):
            engine.dataServer.appendNumpadCode(c, mode: mode)
            engine.transition(to: ComposingState())
            engine.updateUI()
            return true
            
        case .punctuation(let p):
            Logger.shared.logInputCharacter(p, mode: mode)
            var mapped = engine.puncMapper.map(char: p, mode: mode)
            
            let preChar = engine.getPrecedingChar(from: precedingText)
            if let pre = preChar, pre.isNumber {
                if p == "," || p == "." || p == ";" {
                    mapped = p
                }
            }
            
            Logger.shared.log(event: "PUNCTUATION", details: "Input: '\(p)' -> Mapped: '\(mapped)'")
            engine.commitText(mapped)
            return true
            
        case .openPreferences:
            #if os(macOS)
            PreferencesCoordinator.shared.show()
            #endif
            return true
            
        default:
            return false
        }
    }
}

public class ComposingState: InputState {
    
    public func handle(action: KeyAction, engine: CompositionEngine, precedingText: String?) -> Bool {
        let mode = PreferencesManager.shared.currentMode
        
        switch action {
        case .numpadChar(let c):
            engine.hasNavigated = false
            engine.dataServer.appendNumpadCode(c, mode: mode)
            engine.updateUI()
            return true
            
        case .char(let c):
            engine.hasNavigated = false
            let buffer = engine.dataServer.getBuffer()
            
            if buffer.starts(with: "9") {
                if let num = Int(c) {
                    if num >= 1 && num <= 9 {
                        return self.handle(action: .numberSelect(num), engine: engine, precedingText: precedingText)
                    } else if num == 0 {
                        return self.handle(action: .numberSelect(10), engine: engine, precedingText: precedingText)
                    }
                }
            }
            
            if mode == .heMaMode && PreferencesManager.shared.isNumberMode {
                let validChars = "123450"
                if !validChars.contains(c) && !buffer.starts(with: "9") {
                    engine.forceCommit()
                    return false
                }
            }
            
            if mode == .heMaMode && !buffer.starts(with: "9") && !PreferencesManager.shared.isNumberMode {
                if buffer.count >= 4 {
                    if c == "m" {
                        return self.handle(action: .down, engine: engine, precedingText: precedingText)
                    } else {
                        engine.forceCommit()
                        return engine.currentState.handle(action: action, engine: engine, precedingText: precedingText)
                    }
                }
            }
            
            if engine.dataServer.prompt != nil {
                engine.dataServer.prompt = nil
            }
            
            Logger.shared.logInputCharacter(c, mode: mode)
            
            engine.dataServer.appendCode(c, mode: mode)
            
            let newBuffer = engine.dataServer.getBuffer()
            if newBuffer.starts(with: "9") && newBuffer.count == 2, let actionType = CommandTree.shared.getAction(buffer: newBuffer) {
                engine.executeCommand(actionType: actionType)
                return true
            }
            
            let candidates = engine.dataServer.currentCandidates
            Logger.shared.logConversion(input: newBuffer, candidates: candidates, selected: nil)
            engine.updateUI()
            return true
            
        case .backspace:
            engine.hasNavigated = false
            if engine.dataServer.prompt != nil {
                engine.dataServer.prompt = nil
                engine.transition(to: IdleState())
                engine.updateUI()
                return true
            }
            engine.dataServer.backspace(mode: mode)
            if engine.dataServer.getBuffer().isEmpty {
                engine.transition(to: IdleState())
            }
            engine.updateUI()
            return true
            
        case .space:
            engine.hasNavigated = false
            if engine.dataServer.prompt != nil {
                engine.dataServer.prompt = nil
                engine.transition(to: IdleState())
                engine.updateUI()
                return true
            }
            let candidates = engine.dataServer.currentCandidates
            let selectedIndex = engine.dataServer.selectedIndex
            if selectedIndex < candidates.count {
                let selectedCandidate = candidates[selectedIndex]
                Logger.shared.log(event: "SPACE_SELECT", details: "Space selected candidate: '\(selectedCandidate.word)'")
                Logger.shared.logConversion(input: engine.dataServer.getBuffer(), candidates: candidates, selected: selectedCandidate.word)
            }
            
            if !engine.commitSelectedCandidate() {
                engine.forceCommit()
            }
            return true
            
        case .enter:
            engine.hasNavigated = false
            if engine.dataServer.prompt != nil {
                engine.dataServer.prompt = nil
                engine.transition(to: IdleState())
                engine.updateUI()
                return true
            }
            engine.forceCommit()
            return true
            
        case .escape:
            engine.hasNavigated = false
            engine.dataServer.clear()
            engine.transition(to: IdleState())
            engine.updateUI()
            return true
            
        case .numberSelect(let num):
            engine.hasNavigated = false
            let index = num - 1
            let candidates = engine.dataServer.currentCandidates
            
            if index < candidates.count {
                let selectedCandidate = candidates[index]
                Logger.shared.log(event: "NUMBER_SELECT", details: "Number \(num) selected candidate: '\(selectedCandidate.word)'")
                Logger.shared.logConversion(input: engine.dataServer.getBuffer(), candidates: candidates, selected: selectedCandidate.word)
            }
            
            if !engine.commitCandidate(at: index) {
                let charToAppend = num == 10 ? "0" : String(num)
                engine.dataServer.appendCode(charToAppend, mode: mode)
                
                let buffer = engine.dataServer.getBuffer()
                if buffer.starts(with: "9") && buffer.count == 2, let actionType = CommandTree.shared.getAction(buffer: buffer) {
                    engine.executeCommand(actionType: actionType)
                    return true
                }
                
                engine.updateUI()
            }
            return true
            
        case .pageUp, .left:
            engine.hasNavigated = true
            if engine.dataServer.pageUp() {
                engine.updateUI()
            }
            return true
            
        case .pageDown, .right:
            engine.hasNavigated = true
            if engine.dataServer.pageDown() {
                engine.updateUI()
            }
            return true
            
        case .up:
            engine.hasNavigated = true
            engine.dataServer.moveSelectionUp()
            engine.updateUI()
            return true
            
        case .down:
            engine.hasNavigated = true
            engine.dataServer.moveSelectionDown()
            engine.updateUI()
            return true
            
        case .punctuation(let p):
            engine.hasNavigated = false
            if !engine.commitSelectedCandidate() {
                engine.forceCommit()
            }
            
            var mapped = engine.puncMapper.map(char: p, mode: mode)
            
            if let lastChar = engine.lastCommittedChar, lastChar.isNumber {
                if p == "," || p == "." || p == ";" {
                    mapped = p
                }
            }
            
            engine.commitText(mapped)
            return true
            
        case .openPreferences:
            #if os(macOS)
            PreferencesCoordinator.shared.show()
            #endif
            return true
            
        case .forwardDelete, .home, .end, .tab:
            engine.forceCommit()
            return false
            
        case .unknown:
            engine.forceCommit()
            return false
        }
    }
}

public class AssociationState: InputState {
    public func handle(action: KeyAction, engine: CompositionEngine, precedingText: String?) -> Bool {
        switch action {
        case .char(_):
            engine.dataServer.clear()
            engine.transition(to: IdleState())
            engine.updateUI()
            return engine.currentState.handle(action: action, engine: engine, precedingText: precedingText)
            
        case .space:
            engine.hasNavigated = false
            let candidates = engine.dataServer.currentCandidates
            let selectedIndex = engine.dataServer.selectedIndex
            if selectedIndex < candidates.count {
                let selectedCandidate = candidates[selectedIndex]
                engine.commitText(selectedCandidate.word)
                
                let newPrefix = engine.dataServer.associationPrefix + selectedCandidate.word
                engine.dataServer.setAssociation(word: newPrefix)
                
                if engine.dataServer.allCandidates.isEmpty {
                    engine.transition(to: IdleState())
                }
                engine.updateUI()
                return true
            }
            return false
            
        case .numberSelect(let num):
            engine.hasNavigated = false
            let index = num - 1
            let candidates = engine.dataServer.currentCandidates
            if index < candidates.count {
                let selectedCandidate = candidates[index]
                engine.commitText(selectedCandidate.word)
                
                let newPrefix = engine.dataServer.associationPrefix + selectedCandidate.word
                engine.dataServer.setAssociation(word: newPrefix)
                
                if engine.dataServer.allCandidates.isEmpty {
                    engine.transition(to: IdleState())
                }
                engine.updateUI()
                return true
            }
            engine.dataServer.clear()
            engine.transition(to: IdleState())
            engine.updateUI()
            return engine.currentState.handle(action: .char(String(num)), engine: engine, precedingText: precedingText)
            
        case .backspace, .escape:
            engine.dataServer.clear()
            engine.transition(to: IdleState())
            engine.updateUI()
            return true
            
        case .pageUp, .left:
            engine.hasNavigated = true
            if engine.dataServer.pageUp() { engine.updateUI() }
            return true
            
        case .pageDown, .right:
            engine.hasNavigated = true
            if engine.dataServer.pageDown() { engine.updateUI() }
            return true
            
        case .up:
            engine.hasNavigated = true
            engine.dataServer.moveSelectionUp()
            engine.updateUI()
            return true
            
        case .down:
            engine.hasNavigated = true
            engine.dataServer.moveSelectionDown()
            engine.updateUI()
            return true
            
        case .punctuation(_):
            engine.dataServer.clear()
            engine.transition(to: IdleState())
            engine.updateUI()
            return engine.currentState.handle(action: action, engine: engine, precedingText: precedingText)
            
        default:
            engine.dataServer.clear()
            engine.transition(to: IdleState())
            engine.updateUI()
            return false
        }
    }
}