// PreferencesWindowController.swift
#if os(macOS)
import Cocoa
#else
import UIKit
#endif
import SwiftUI

#if os(macOS)
public class PreferencesCoordinator: NSObject {
    public static let shared = PreferencesCoordinator()
    private var windowController: NSWindowController?
    
    public func show() {
        if windowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "和码输入法设置"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView())
            window.delegate = self
            windowController = NSWindowController(window: window)
        }
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
    }
}

extension PreferencesCoordinator: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
#endif

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Text("通用设置") }
            HelpView().tabItem { Text("使用说明") }
            AboutView().tabItem { Text("关于") }
        }
        .padding()
        #if os(macOS)
        .frame(width: 600, height: 480)
        #endif
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var prefs = PreferencesManager.shared
    var body: some View {
        Form {
            Section(header: Text("基础配置").font(.headline).padding(.bottom, 5)) {
                Toggle("简体模式", isOn: $prefs.isSimplified)
                Toggle("开启词组输入", isOn: $prefs.enablePhrase)
                Toggle("开启拼音反查", isOn: $prefs.enablePinyin)
                
                HStack {
                    Text("候选词数量:")
                    Stepper("\(prefs.pageSize)", value: $prefs.pageSize, in: 5...12)
                }
            }
            
            Divider().padding(.vertical, 10)
            
            Section(header: Text("快捷键设置").font(.headline).padding(.bottom, 5)) {
                Picker("中英切换快捷键:", selection: $prefs.switchLangShortcut) {
                    Text("左 Shift").tag(0)
                    Text("右 Shift").tag(1)
                    Text("Ctrl").tag(2)
                    Text("无").tag(3)
                }
                #if os(macOS)
                .pickerStyle(MenuPickerStyle())
                .frame(width: 250)
                #endif
                
                Picker("命令模式快捷键:", selection: $prefs.commandShortcut) {
                    Text("Ctrl").tag(0)
                    Text("右 Shift").tag(1)
                    Text("左 Shift").tag(2)
                    Text("无").tag(3)
                }
                #if os(macOS)
                .pickerStyle(MenuPickerStyle())
                .frame(width: 250)
                #endif
                
                Text("注：单按修饰键触发。若两者设置为同一按键，优先响应中英切换。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
            
            Spacer()
        }
        .padding(20)
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("快捷键说明").font(.headline)
                    HStack {
                        Text("中英切换:")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        Text("默认单按 左 Shift 键")
                    }
                    HStack {
                        Text("命令模式:")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        Text("默认单按 Ctrl 键 (输入框出现 '9')")
                    }
                    HStack {
                        Text("打开设置:")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        Text("Ctrl + Option + P")
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("命令模式 (输入 9 触发)").font(.headline)
                    Text("在中文状态下，输入 9 即可进入命令模式，随后输入对应数字执行快捷操作：")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        GridRow {
                            Text("91").fontWeight(.bold).foregroundColor(.accentColor)
                            Text("打开偏好设置")
                        }
                        GridRow {
                            Text("92").fontWeight(.bold).foregroundColor(.accentColor)
                            Text("切换 简体/繁体")
                        }
                        GridRow {
                            Text("93").fontWeight(.bold).foregroundColor(.accentColor)
                            Text("切换 和码/拼音 模式")
                        }
                        GridRow {
                            Text("94").fontWeight(.bold).foregroundColor(.accentColor)
                            Text("切换 字母/数字 键盘模式")
                        }
                        GridRow {
                            Text("95").fontWeight(.bold).foregroundColor(.accentColor)
                            Text("开启/关闭 词组输入")
                        }
                        GridRow {
                            Text("96").fontWeight(.bold).foregroundColor(.accentColor)
                            Text("进入特殊符号面板")
                        }
                    }
                    .padding(.leading, 10)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding(20)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 15) {
            Spacer()
            #if os(macOS)
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable().frame(width: 64, height: 64)
            #else
            Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                .resizable().frame(width: 64, height: 64)
            #endif
            
            Text("和码输入法").font(.title).bold()
            
            Text("学中文就上HeChinese")
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)

            Divider().padding(.horizontal, 50)
            
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "message.fill").foregroundColor(.green)
                    Text("微信公众号：HeChinese和码中文国际")
                }
                
                HStack {
                    Image(systemName: "link").foregroundColor(.blue)
                    Button("访问官网: www.hechinese.net") {
                        if let url = URL(string: "https://www.hechinese.net") {
                            #if os(macOS)
                            NSWorkspace.shared.open(url)
                            #else
                            UIApplication.shared.open(url)
                            #endif
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(LinkButtonStyle())
                    #endif
                }
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 80, height: 80)
                Image(systemName: "qrcode").resizable()
                    .frame(width: 40, height: 40).opacity(0.2)
            }.padding(.top, 10)
            
            Spacer()
            Text("Version 1.0.0 (Universal)").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }
}