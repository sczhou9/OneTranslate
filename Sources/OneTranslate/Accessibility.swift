import AppKit
import ApplicationServices
import IOKit.hid

struct TextSnapshot {
    let element: AXUIElement
    let text: String
    let usesSelection: Bool
    let fullText: String
    let range: NSRange
}

// AX ranges use UTF-16 offsets, including for Chinese and emoji.
struct TextEditPlan {
    let before: String
    let range: NSRange
    let replacement: String

    var after: String? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= (before as NSString).length,
              range.length <= (before as NSString).length - range.location else { return nil }
        return (before as NSString).replacingCharacters(in: range, with: replacement)
    }
    var inverse: TextEditPlan? {
        guard let after else { return nil }
        return TextEditPlan(before: after,
            range: NSRange(location: range.location, length: (replacement as NSString).length),
            replacement: (before as NSString).substring(with: range))
    }
}

@MainActor
final class TextReplacer {
    private let systemElement = AXUIElementCreateSystemWide()
    private var undoRecord: (element: AXUIElement, plan: TextEditPlan)?
    var canUndo: Bool { undoRecord != nil }

    func accessibilityIsGranted() -> Bool { AXIsProcessTrusted() }
    func inputMonitoringIsGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func snapshot() -> TextSnapshot? {
        guard let element = focusedElement(),
              stringValue(of: element, attribute: kAXSubroleAttribute) != kAXSecureTextFieldSubrole,
              let full = stringValue(of: element, attribute: kAXValueAttribute) else { return nil }
        let selected = selectedRange(element)
        let selectedText = stringValue(of: element, attribute: kAXSelectedTextAttribute) ?? ""
        // Never translate the entire field when a selection exists but its range is unavailable.
        guard selectedText.isEmpty || (selected?.length ?? 0) > 0 else { return nil }
        let usesSelection = (selected?.length ?? 0) > 0
        let range = usesSelection ? selected! : NSRange(location: 0, length: (full as NSString).length)
        let plan = TextEditPlan(before: full, range: range, replacement: "")
        guard plan.after != nil else { return nil }
        let text = (full as NSString).substring(with: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return TextSnapshot(element: element, text: text, usesSelection: usesSelection, fullText: full, range: range)
    }

    func replace(_ snapshot: TextSnapshot, with translation: String) async -> Bool {
        let plan = TextEditPlan(before: snapshot.fullText, range: snapshot.range, replacement: translation)
        guard isFocused(snapshot.element),
              !snapshot.usesSelection || selectedRange(snapshot.element) == snapshot.range else { return false }
        guard await apply(plan, to: snapshot.element) else { return false }
        if let inverse = plan.inverse { undoRecord = (snapshot.element, inverse) }
        return true
    }

    func undo() async -> Bool {
        guard let record = undoRecord else { return false }
        // Refuse to overwrite edits made after translation.
        guard stringValue(of: record.element, attribute: kAXValueAttribute) == record.plan.before else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(record.element, &pid)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        AXUIElementSetAttributeValue(record.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard await apply(record.plan, to: record.element) else { return false }
        undoRecord = nil
        return true
    }

    private func apply(_ plan: TextEditPlan, to element: AXUIElement) async -> Bool {
        guard let expected = plan.after, isFocused(element),
              stringValue(of: element, attribute: kAXValueAttribute) == plan.before else { return false }
        if expected == plan.before { return true }

        // Set the precise range first, including when undoing a previous edit.
        if selectedRange(element) != plan.range {
            guard setRange(plan.range, on: element), selectedRange(element) == plan.range else { return false }
        }
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, plan.replacement as CFString)
        if await verify(expected, on: element, attempts: 3) { return true }
        guard isFocused(element),
              stringValue(of: element, attribute: kAXValueAttribute) == plan.before,
              selectedRange(element) == plan.range else { return false }

        // Some editors expose a range but ignore AXSelectedText writes. Paste into
        // that exact range, then read back the field before reporting success.
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        board.clearContents()
        guard board.setString(plan.replacement, forType: .string) else { return false }
        let pasteChangeCount = board.changeCount
        defer {
            // Do not overwrite something the user copied while the paste ran.
            if board.changeCount == pasteChangeCount {
                board.clearContents()
                let items = saved.map { values -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                board.writeObjects(items)
            }
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return await verify(expected, on: element, attempts: 20)
    }

    private func verify(_ expected: String, on element: AXUIElement, attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            if stringValue(of: element, attribute: kAXValueAttribute) == expected { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
    private func isFocused(_ element: AXUIElement) -> Bool {
        guard let focused = focusedElement() else { return false }
        return CFEqual(focused, element)
    }
    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func stringValue(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func setRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var value = CFRange(location: range.location, length: range.length)
        guard let axValue = AXValueCreate(.cfRange, &value) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue) == .success
    }
}

final class GlobalFunctionKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private let onPress: () -> Void
    private let onRelease: () -> Void

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(
            1 << CGEventType.flagsChanged.rawValue
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalFunctionKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        )

        guard let eventTap else { return false }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }
        let pressed = event.flags.contains(.maskSecondaryFn)
        if pressed && !isPressed {
            isPressed = true
            onPress()
        } else if !pressed && isPressed {
            isPressed = false
            onRelease()
        }
    }
}
