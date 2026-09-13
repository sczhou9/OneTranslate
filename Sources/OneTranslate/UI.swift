import AppKit
import QuartzCore
import ServiceManagement

private let accent = NSColor(calibratedRed: 0.36, green: 0.32, blue: 0.9, alpha: 1)

final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.contains(.command), let editor = firstResponder as? NSText {
            switch event.keyCode {
            case 9: editor.paste(nil); return
            case 8: editor.copy(nil); return
            case 7: editor.cut(nil); return
            case 0: editor.selectAll(nil); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

final class HUDController {
    private var panel: NSPanel?
    private let ring = CAShapeLayer()
    private let symbol = NSImageView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var generation = 0

    func show(_ message: String, error: Bool = false, progress: Bool = false) {
        generation += 1
        let current = generation
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 56, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            let root = NSView(frame: panel.frame)
            root.wantsLayer = true
            root.layer?.masksToBounds = true
            ring.frame = NSRect(x: 0, y: 0, width: 56, height: 56)
            ring.path = CGPath(ellipseIn: CGRect(x: 4, y: 4, width: 48, height: 48), transform: nil)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = NSColor(calibratedRed: 0.7, green: 0.68, blue: 1, alpha: 1).cgColor
            ring.lineWidth = 2.5
            ring.lineCap = .round
            ring.strokeEnd = 0.72
            root.layer?.addSublayer(ring)
            symbol.frame = NSRect(x: 17, y: 17, width: 22, height: 22)
            symbol.contentTintColor = .white
            symbol.imageScaling = .scaleProportionallyUpOrDown
            root.addSubview(symbol)
            errorLabel.font = .systemFont(ofSize: 12, weight: .medium)
            errorLabel.textColor = .white
            errorLabel.maximumNumberOfLines = 4
            root.addSubview(errorLabel)
            panel.contentView = root
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let size = error ? NSSize(width: 340, height: 100) : NSSize(width: 56, height: 56)
        panel.setContentSize(size)
        panel.contentView?.layer?.cornerRadius = error ? 22 : 28
        panel.contentView?.layer?.backgroundColor = NSColor(calibratedRed: error ? 0.28 : 0.12, green: 0.12, blue: 0.22, alpha: 1).cgColor
        panel.contentView?.setAccessibilityLabel(message)
        symbol.image = NSImage(systemSymbolName: error ? "exclamationmark.circle" : "character.bubble.fill", accessibilityDescription: message)
        errorLabel.isHidden = !error
        errorLabel.stringValue = message
        errorLabel.frame = NSRect(x: 64, y: 14, width: 260, height: 72)
        ring.removeAllAnimations()
        ring.isHidden = !progress
        if progress {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.toValue = Double.pi * 2
            animation.duration = 1.2
            animation.repeatCount = .infinity
            ring.add(animation, forKey: "spin")
        }
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24))
        panel.orderFrontRegardless()
        if !progress {
            DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 6 : 1)) { [weak self] in
                guard self?.generation == current else { return }
                self?.hide()
            }
        }
    }
    func hide() {
        generation += 1
        ring.removeAllAnimations()
        panel?.orderOut(nil)
    }
}

final class SettingsWindowController: NSWindowController {
    private let onSave: (AppSettings) -> Void
    private var settings: AppSettings
    private let endpoint = NSTextField()
    private let apiKey = NSSecureTextField()
    private let model = NSTextField()
    private let source = NSPopUpButton()
    private let target = NSPopUpButton()
    private let reverse = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let tone = NSPopUpButton()
    private let permissions = NSTextField(wrappingLabelWithString: "")
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch OneTranslate at login", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")

    init(settings: AppSettings, onSave: @escaping (AppSettings) -> Void) {
        self.settings = settings
        self.onSave = onSave
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 740), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "OneTranslate"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        configure()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        return label
    }

    private func configure() {
        guard let root = window?.contentView else { return }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        let save = NSButton(title: "Save changes", target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        save.bezelColor = accent
        save.keyEquivalent = "\r"
        save.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(save)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -16),
            save.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            save.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 20, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let icon = NSImageView()
        icon.image = NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "")
        icon.widthAnchor.constraint(equalToConstant: 58).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let titles = NSStackView(views: [label("A little key. A wider world.", size: 21, weight: .semibold), label("Translate in place, with your own model.", size: 13, secondary: true)])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 5
        let header = NSStackView(views: [icon, titles])
        header.spacing = 14
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(card("keyboard", "One key, two directions", [
            label("fn  →  Translate the focused field", size: 14, weight: .medium),
            label("Select words + fn  →  Reverse only that selection", size: 13),
            label("Hold and release Fn. The animated circle stays visible while your model is working.", secondary: true)
        ]))
        for (field, value, placeholder) in [(endpoint, settings.endpoint, "https://…/v1/chat/completions"), (apiKey, settings.apiKey, "Optional for a local model"), (model, settings.model, "Model ID")] {
            field.stringValue = value
            field.placeholderString = placeholder
            field.font = .systemFont(ofSize: 13)
            field.isEditable = true
            field.isSelectable = true
            field.bezelStyle = .roundedBezel
            field.usesSingleLineMode = true
        }
        stack.addArrangedSubview(card("server.rack", "Your model", [row("Endpoint", endpoint), row("API key", apiKey), row("Model", model), label("Text goes directly to this endpoint. No OneTranslate relay.", secondary: true)]))
        for (popup, values, selected) in [(source, ["Auto"] + AppSettings.languages, settings.sourceLanguage), (target, AppSettings.languages, settings.targetLanguage), (reverse, ["Source language"] + AppSettings.languages, settings.reverseLanguage), (mode, AppSettings.modes, settings.mode), (tone, AppSettings.styles, settings.style)] {
            popup.addItems(withTitles: values)
            popup.selectItem(withTitle: selected)
        }
        stack.addArrangedSubview(card("arrow.left.arrow.right", "Language & expression", [
            row("From", source), row("To", target), row("Reverse to", reverse),
            label("Reverse uses your source language. When From is Auto, it uses your Mac’s preferred language. Choose an explicit reverse language to override it.", secondary: true),
            row("Style", mode), row("Tone", tone)
        ]))
        permissions.font = .systemFont(ofSize: 12)
        let accessibility = NSButton(title: "Accessibility…", target: self, action: #selector(openAccessibility))
        let input = NSButton(title: "Input Monitoring…", target: self, action: #selector(openInput))
        accessibility.bezelStyle = .rounded
        input.bezelStyle = .rounded
        stack.addArrangedSubview(card("checkmark.shield", "Permissions", [permissions, NSStackView(views: [accessibility, input])]))
        launchAtLogin.target = self
        launchAtLogin.action = #selector(changeLoginSetting)
        loginStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        refreshLoginStatus()
        stack.addArrangedSubview(card("power", "Startup & undo", [
            launchAtLogin, loginStatus,
            label("To restore the original wording, choose Undo last translation from the menu-bar icon. The last original is held only in memory until you quit. Undo stops if you have since edited the field.", secondary: true)
        ]))
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true }
    }

    private func card(_ symbol: String, _ title: String, _ views: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 0.5
        box.cornerRadius = 16
        box.contentViewMargins = .zero
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = accent
        let heading = NSStackView(views: [icon, label(title, size: 13, weight: .semibold)])
        heading.spacing = 8
        let stack = NSStackView(views: [heading] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = box.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return box
    }
    private func row(_ title: String, _ control: NSView) -> NSView {
        let name = label(title, secondary: true)
        name.widthAnchor.constraint(equalToConstant: 78).isActive = true
        let row = NSStackView(views: [name, control])
        row.spacing = 12
        row.alignment = .centerY
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }
    @objc private func saveSettings() {
        settings.endpoint = endpoint.stringValue
        settings.apiKey = apiKey.stringValue
        settings.model = model.stringValue
        settings.sourceLanguage = source.titleOfSelectedItem ?? "Auto"
        settings.targetLanguage = target.titleOfSelectedItem ?? "English"
        settings.reverseLanguage = reverse.titleOfSelectedItem ?? "Source language"
        settings.mode = mode.titleOfSelectedItem ?? "Elegant"
        settings.style = tone.titleOfSelectedItem ?? "Friendly"
        onSave(settings)
        close()
    }
    override func showWindow(_ sender: Any?) {
        refreshLoginStatus()
        super.showWindow(sender)
    }
    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin.state = status == .enabled || status == .requiresApproval ? .on : .off
        switch status {
        case .enabled: loginStatus.stringValue = "Enabled for your macOS account."
        case .requiresApproval: loginStatus.stringValue = "Approval required in System Settings → General → Login Items."
        case .notRegistered: loginStatus.stringValue = "Off. Enable to start quietly in the menu bar after login."
        default: loginStatus.stringValue = "Install the app in Applications to enable launch at login."
        }
    }
    @objc private func changeLoginSetting() {
        do {
            if launchAtLogin.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            loginStatus.stringValue = "Could not change login startup: " + error.localizedDescription
        }
    }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openInput() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    func setPermissionStatus(_ status: String, error: Bool) {
        permissions.stringValue = status
        permissions.textColor = error ? .systemOrange : .secondaryLabelColor
    }
}
