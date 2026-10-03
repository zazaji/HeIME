// ModifierTracker.swift
#if os(macOS)
import Cocoa

public class ModifierTracker {
    private var leftShiftDown: Bool = false
    private var rightShiftDown: Bool = false
    private var ctrlDown: Bool = false
    private var hasOtherKeyPressed: Bool = false
    
    public init() {}
    
    public func handleFlagsChanged(event: NSEvent) -> (toggledLeftShift: Bool, toggledRightShift: Bool, toggledCtrl: Bool) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags
        
        var toggledLeftShift = false
        var toggledRightShift = false
        var toggledCtrl = false
        
        if keyCode == 56 {
            if flags.contains(.shift) {
                self.leftShiftDown = true
                self.hasOtherKeyPressed = false
            } else {
                if self.leftShiftDown && !self.hasOtherKeyPressed {
                    toggledLeftShift = true
                }
                self.leftShiftDown = false
            }
        }
        
        if keyCode == 60 {
            if flags.contains(.shift) {
                self.rightShiftDown = true
                self.hasOtherKeyPressed = false
            } else {
                if self.rightShiftDown && !self.hasOtherKeyPressed {
                    toggledRightShift = true
                }
                self.rightShiftDown = false
            }
        }
        
        if keyCode == 59 || keyCode == 62 {
            if flags.contains(.control) {
                self.ctrlDown = true
                self.hasOtherKeyPressed = false
            } else {
                if self.ctrlDown && !self.hasOtherKeyPressed {
                    toggledCtrl = true
                }
                self.ctrlDown = false
            }
        }
        
        return (toggledLeftShift, toggledRightShift, toggledCtrl)
    }
    
    public func registerOtherKeyPress() {
        if self.leftShiftDown || self.rightShiftDown || self.ctrlDown {
            self.hasOtherKeyPressed = true
        }
    }
}
#endif