// main.swift
#if os(macOS)
import Cocoa
import InputMethodKit

let bundleIdentifier = "hezi.inputmethod.HeInput"

Logger.shared.log(
    event: "START",
    details: "Starting IMKServer for \(bundleIdentifier)"
)

let serverName = bundleIdentifier + "_Connection"

guard let server = IMKServer(
    name: serverName,
    bundleIdentifier: bundleIdentifier
) else {
    let errorMsg = "Failed to initialize IMKServer! " +
                   "Check Info.plist InputMethodConnectionName " +
                   "and entitlements Mach Port."
                   
    Logger.shared.log(
        event: "FATAL_ERROR",
        details: errorMsg
    )
    fatalError(errorMsg)
}

var appDelegate: AppDelegate?

Task { @MainActor in
    let app = NSApplication.shared
    appDelegate = AppDelegate(server: server)
    app.delegate = appDelegate
    
    Logger.shared.log(
        event: "RUNLOOP",
        details: "Entering NSApplication run loop"
    )
    
    app.run()
}

RunLoop.main.run()
#endif