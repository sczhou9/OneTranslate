import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settingsStore = UserDefaults.standard
    private let service = TranslationService()
    private let replacer = TextReplacer()
    private let hud = HUDController()
    private var statusItem: NSStatusItem!
    private var monitor: GlobalFunctionKeyMonitor!
    private var monitorRetry: Timer?
    private var monitorActive = false
    private var settingsWindow: SettingsWindowController?
    private var translating = false
    private var undoItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        monitor = GlobalFunctionKeyMonitor(
            onPress: {},
            onRelease: { [weak self] in self?.translateFocusedText() }
        )

        startMonitor()
        if settingsStore.string(forKey: "endpoint") == nil {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "Translate / reverse selection  (Fn)", action: #selector(translateFromMenu), keyEquivalent: ""))
        undoItem = NSMenuItem(title: "Undo last translation", action: #selector(undoTranslation), keyEquivalent: "")
        menu.addItem(undoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit OneTranslate", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func translateFromMenu() {
        translateFocusedText()
    }

    func menuWillOpen(_ menu: NSMenu) {
        undoItem.isEnabled = replacer.canUndo && !translating
    }

    @objc private func undoTranslation() {
        guard !translating else { return }
        translating = true
        updateStatusIcon()
        Task { @MainActor in
            defer { translating = false; updateStatusIcon() }
            if await replacer.undo() {
                hud.show("Original text restored")
            } else {
                hud.show("Cannot undo: the field changed or is no longer editable.", error: true)
            }
        }
    }

    private func updateStatusIcon() {
        let image = NSImage(systemSymbolName: translating ? "ellipsis.bubble" : "character.bubble", accessibilityDescription: translating ? "OneTranslate — Translating" : "OneTranslate")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = translating ? "Translating…" : "OneTranslate · Fn to translate"
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: AppSettings(defaults: settingsStore)) { [weak self] settings in
                settings.save(to: self?.settingsStore ?? .standard)
            }
        }
        settingsWindow?.showWindow(nil)
        updatePermissionStatus()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startMonitor() {
        if replacer.accessibilityIsGranted() && replacer.inputMonitoringIsGranted() && monitor.start() {
            monitorActive = true
            monitorRetry?.invalidate()
            monitorRetry = nil
            updatePermissionStatus()
            return
        }
        monitorActive = false
        monitorRetry?.invalidate()
        monitorRetry = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(retryMonitor), userInfo: nil, repeats: true)
        updatePermissionStatus()
    }

    @objc private func retryMonitor() {
        if replacer.accessibilityIsGranted() && replacer.inputMonitoringIsGranted() && monitor.start() {
            monitorActive = true
            monitorRetry?.invalidate()
            monitorRetry = nil
        }
        updatePermissionStatus()
    }

    private func updatePermissionStatus() {
        let accessibility = replacer.accessibilityIsGranted()
        let inputMonitoring = replacer.inputMonitoringIsGranted()
        let status: String
        if monitorActive && inputMonitoring {
            status = "Accessibility: enabled · Input Monitoring: active for Fn"
        } else if accessibility && !inputMonitoring {
            status = "Accessibility: enabled · Input Monitoring: required for Fn"
        } else {
            status = "Accessibility: not detected · Input Monitoring: required for Fn"
        }
        settingsWindow?.setPermissionStatus(status, error: !accessibility || !inputMonitoring || !monitorActive)
    }

    private func translateFocusedText() {
        guard !translating else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        guard replacer.accessibilityIsGranted() else {
            hud.show("This OneTranslate.app copy is not authorized under Accessibility. Add it in System Settings.", error: true)
            return
        }
        guard let snapshot = replacer.snapshot() else {
            hud.show("Select text in an editable field. This app must expose its text and selection to macOS Accessibility.", error: true)
            return
        }

        translating = true
        updateStatusIcon()
        var settings = AppSettings(defaults: settingsStore)
        let direction = settings.direction(forSelection: snapshot.usesSelection)
        settings.sourceLanguage = direction.source
        settings.targetLanguage = direction.target
        hud.show(snapshot.usesSelection ? "Reverse translating…" : "Translating…", progress: true)
        let text = snapshot.text

        Task { @MainActor in
            defer { translating = false; updateStatusIcon() }
            do {
                let translation = try await service.translate(text, settings: settings)
                if await replacer.replace(snapshot, with: translation) {
                    hud.hide()
                } else {
                    hud.show("Could not verify replacement. Keep the original field focused and editable; its text and selection must stay unchanged.", error: true)
                }
            } catch {
                hud.show(error.localizedDescription, error: true)
            }
        }
    }
}
