// CandidatesWindow.swift
#if os(macOS)
import Cocoa
#else
import UIKit
#endif
import SwiftUI
import Combine

public enum CandidateAction {
    case select(Int)
    case toggleMode
    case toggleSimp
    case toggleEng
    case toggleNumberMode
    case openPreferences
}

#if os(macOS)
public class CandidatesWindow: NSPanel {
    public static let shared = CandidatesWindow()
    
    private var hostingView: NSHostingView<CandidatesView>!
    private var viewModel = CandidatesViewModel()
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 100), 
            styleMask:[.borderless, .nonactivatingPanel], 
            backing: .buffered, 
            defer: false
        )
        
        self.level = .popUpMenu
        self.hidesOnDeactivate = false 
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        
        self.hostingView = NSHostingView(rootView: CandidatesView(viewModel: self.viewModel))
        self.contentView = self.hostingView
    }
    
    public func update(buffer: String, candidates: [CandidateItem], selectedIndex: Int, prompt: String?, reverseLookupText: String?, cursorRect: NSRect, onAction: @escaping (CandidateAction) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.update(buffer: buffer, candidates: candidates, selectedIndex: selectedIndex, prompt: prompt, reverseLookupText: reverseLookupText, cursorRect: cursorRect, onAction: onAction)
            }
            return
        }
        
        if buffer.isEmpty && prompt == nil && candidates.isEmpty {
            self.hide()
            return
        }
        
        self.viewModel.buffer = buffer
        self.viewModel.prompt = prompt
        self.viewModel.candidates = candidates
        self.viewModel.selectedIndex = selectedIndex
        self.viewModel.reverseLookupText = reverseLookupText
        self.viewModel.onAction = onAction
        
        self.hostingView.rootView = CandidatesView(viewModel: self.viewModel)
        self.hostingView.layout()
        
        let fittingSize = self.hostingView.fittingSize
        let width = max(200, fittingSize.width)
        let height = fittingSize.height
        
        self.setContentSize(NSSize(width: width, height: height))
        
        var origin = cursorRect.origin
        origin.y -= height + 4
        
        let screen = NSScreen.screens.first { $0.frame.contains(cursorRect.origin) } ?? NSScreen.main
        
        if let screen = screen {
            let visibleFrame = screen.visibleFrame
            if origin.x + width > visibleFrame.maxX {
                origin.x = visibleFrame.maxX - width
            }
            if origin.y < visibleFrame.minY {
                origin.y = cursorRect.maxY + 4
            }
        }
        
        self.setFrameOrigin(origin)
        self.orderFrontRegardless()
    }
    
    public func hide() {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.hide()
            }
            return
        }
        self.orderOut(nil)
    }
}
#endif

public class CandidatesViewModel: ObservableObject {
    @Published public var buffer: String = ""
    @Published public var prompt: String? = nil
    @Published public var candidates:[CandidateItem] = []
    @Published public var selectedIndex: Int = 0
    @Published public var reverseLookupText: String? = nil
    public var onAction: ((CandidateAction) -> Void)? = nil
}

public struct CandidatesView: View {
    @ObservedObject var viewModel: CandidatesViewModel
    @ObservedObject var prefs = PreferencesManager.shared
    
    private func getDisplayCode(code: String) -> String {
        if code.starts(with: "9") {
            return code
        }
        
        if PreferencesManager.shared.currentMode != .heMaMode { return code }
        
        if code.contains(where: { $0.isNumber }) {
            return code
        }
        
        let mapped = code.lowercased().compactMap { HeMaCore.charToCodeMap[$0] }
        return mapped.joined(separator: " ")
    }
    
    private func getFilteredDisplayCode(candidateCode: String, buffer: String) -> String {
        if candidateCode.starts(with: "9") && candidateCode.count <= 3 {
            return candidateCode
        }
        
        if PreferencesManager.shared.currentMode == .pinYinMode {
            return ""
        }
        
        var numericBuffer = ""
        for char in buffer {
            if let code = HeMaCore.charToCodeMap[char] {
                numericBuffer += code
            } else if char.isNumber {
                numericBuffer += String(char)
            } else {
                numericBuffer += String(char)
            }
        }
        
        let codeParts = candidateCode.split(separator: " ").map { String($0) }
        var bufferIndex = 0
        let bufferChars = Array(numericBuffer)
        var remainingParts = [String]()
        
        for part in codeParts {
            if bufferIndex < bufferChars.count {
                let partChars = Array(part)
                var matchCount = 0
                for i in 0..<partChars.count {
                    if bufferIndex + i < bufferChars.count {
                        let bChar = bufferChars[bufferIndex + i]
                        // 架构级优化：允许通配符 0 匹配候选词的任意数字，确保剩余编码显示准确
                        if partChars[i] == bChar || bChar == "0" {
                            matchCount += 1
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }
                bufferIndex += matchCount
                
                if matchCount < partChars.count {
                    remainingParts.append(String(partChars[matchCount...]))
                }
            } else {
                remainingParts.append(part)
            }
        }
        
        return remainingParts.joined(separator: " ")
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !viewModel.buffer.isEmpty && viewModel.prompt == nil {
                HStack(spacing: 8) {
                    #if os(macOS)
                    if let nsImage = NSImage(named: "he_icon") {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.onAction?(.openPreferences)
                            }
                    } else {
                        Image(systemName: "keyboard")
                            .frame(width: 16, height: 16)
                    }
                    #else
                    if let uiImage = UIImage(named: "he_icon") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.onAction?(.openPreferences)
                            }
                    } else {
                        Image(systemName: "keyboard")
                            .frame(width: 16, height: 16)
                    }
                    #endif
                    
                    let displayBuffer = getDisplayCode(code: viewModel.buffer)
                    if viewModel.buffer == "9" {
                        Text("特殊符号/命令 (9)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                    } else if !displayBuffer.isEmpty {
                        Text(displayBuffer)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.secondary.opacity(0.1))
                
                Divider().background(Color.secondary.opacity(0.2))
            }
            
            VStack(spacing: 0) {
                if let prompt = viewModel.prompt {
                    HStack(spacing: 12) {
                        Text(prompt)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Color.clear)
                    .padding(.horizontal, 8)
                } else {
                    ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                        HStack(spacing: 12) {
                            Text("\(index == 9 ? 0 : index + 1)")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(index == viewModel.selectedIndex ? .white : .secondary)
                                .frame(width: 20, alignment: .trailing)
                            
                            Text(candidate.word)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(index == viewModel.selectedIndex ? .white : .primary)
                            
                            Spacer(minLength: 16)
                            
                            Text(getFilteredDisplayCode(candidateCode: candidate.code, buffer: viewModel.buffer))
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundColor(index == viewModel.selectedIndex ? .white.opacity(0.8) : .secondary.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(index == viewModel.selectedIndex ? Color.accentColor : Color.clear)
                        .cornerRadius(6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.onAction?(.select(index))
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            
            if let reverseText = viewModel.reverseLookupText, let selectedCandidate = viewModel.candidates.indices.contains(viewModel.selectedIndex) ? viewModel.candidates[viewModel.selectedIndex] : nil {
                Divider().background(Color.secondary.opacity(0.2))
                HStack(spacing: 8) {
                    let labelFull = reverseText.components(separatedBy: ": ").first ?? "编"
                    let labelChar = String(labelFull.prefix(1))
                    
                    Text(labelChar)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    
                    HStack(spacing: 4) {
                        Text(selectedCandidate.word)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                        
                        let encoding = reverseText.components(separatedBy: ": ").last ?? reverseText
                        Text(encoding)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            
            Divider().background(Color.secondary.opacity(0.2))
            
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    if prefs.currentMode == .englishMode {
                        ActionButton(title: "英") { viewModel.onAction?(.toggleEng) }
                        ActionButton(title: "⚙️") { viewModel.onAction?(.openPreferences) }
                    } else if prefs.currentMode == .pinYinMode {
                        ActionButton(title: "中") { viewModel.onAction?(.toggleEng) }
                        ActionButton(title: prefs.isSimplified ? "简" : "繁") { viewModel.onAction?(.toggleSimp) }
                        if prefs.enablePinyin {
                            ActionButton(title: "拼") { viewModel.onAction?(.toggleMode) }
                        }
                        ActionButton(title: "⚙️") { viewModel.onAction?(.openPreferences) }
                    } else {
                        ActionButton(title: "中") { viewModel.onAction?(.toggleEng) }
                        ActionButton(title: prefs.isSimplified ? "简" : "繁") { viewModel.onAction?(.toggleSimp) }
                        if prefs.enablePinyin {
                            ActionButton(title: "和") { viewModel.onAction?(.toggleMode) }
                        }
                        ActionButton(title: prefs.isNumberMode ? "数" : "字") { viewModel.onAction?(.toggleNumberMode) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 200)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
    }
}

struct ActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isHovered ? .white : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isHovered ? Color.accentColor : Color.secondary.opacity(0.15))
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture {
                action()
            }
            #if os(macOS)
            .onHover { hovering in
                isHovered = hovering
            }
            #endif
    }
}

#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#else
struct VisualEffectView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}
#endif