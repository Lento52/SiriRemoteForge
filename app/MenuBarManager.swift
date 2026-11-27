//
//  MenuBarManager.swift
//  siriRemote
//
//  The menu-bar status item: a remote icon, a connection-status line, and
//  Settings… / Quit. All button / ring / gesture mapping lives in Settings → Layout, driven by
//  the config engine — there are no mapping submenus here.
//

import AppKit

/// Trackpad two-finger scroll speed → pixels-per-unit scale (used by TouchHandler).
enum ScrollSpeed: String, CaseIterable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"

    var scale: CGFloat {
        switch self {
        case .slow:   return 150.0
        case .medium: return 300.0
        case .fast:   return 500.0
        }
    }
}

final class MenuBarManager {

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let statusMenuItem: NSMenuItem
    private let permissionMenuItem: NSMenuItem
    private final class StatusDot: NSView {
        var isRecording = false {
            didSet { if oldValue != isRecording { needsDisplay = true } }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            (isRecording ? NSColor.systemRed : NSColor.systemGreen).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
    }

    enum VoiceSource { case remoteShortcut, dictation }

    private let statusDot = StatusDot()
    private var voiceSources = Set<VoiceSource>()
    private var isConnected = false
    private var permissionsReady = false
    private var demoRemoteVisible = false
    private var availableUpdateVersion: String?
    private var localeObserver: NSObjectProtocol?

    /// Two-finger scroll scale (see `ScrollSpeed`).
    private(set) var scrollSpeed: ScrollSpeed = .medium

    /// Set by the AppDelegate to open the SwiftUI settings window.
    var onOpenSettings: (() -> Void)?
    /// Set by the AppDelegate to re-open the first-run setup guide.
    var onOpenSetup: (() -> Void)?
    /// Set by the AppDelegate to present Sparkle's standard update UI.
    var onCheckForUpdates: (() -> Void)?
    /// Set by the AppDelegate to show/hide the live, presentation-oriented remote visualiser.
    var onToggleDemoMode: (() -> Void)?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        self.menu = NSMenu()
        self.statusMenuItem = NSMenuItem(title: L("Status: Disconnected"), action: nil, keyEquivalent: "")
        self.permissionMenuItem = NSMenuItem(
            title: L("Permissions: Checking…"), action: nil, keyEquivalent: ""
        )
        setupMenuBar()
        localeObserver = NotificationCenter.default.addObserver(
            forName: Loc.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.relocalize() }
    }

    deinit {
        if let observer = localeObserver { NotificationCenter.default.removeObserver(observer) }
    }

    /// Rebuild the menu and refresh the status line in the current language.
    private func relocalize() {
        rebuildMenu()
        statusMenuItem.title = isConnected ? L("Status: Connected ✓") : L("Status: Disconnected")
        updatePermissionStatus(ready: permissionsReady)
    }

    private func refreshStatusDot() {
        statusDot.isRecording = !voiceSources.isEmpty
        statusDot.isHidden = !isConnected || (!permissionsReady && !statusDot.isRecording)
    }

    func setVoiceActive(_ active: Bool, source: VoiceSource) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if active { self.voiceSources.insert(source) } else { self.voiceSources.remove(source) }
            self.refreshStatusDot()
        }
    }

    // MARK: - Menu

    private func setupMenuBar() {
        guard let button = statusItem.button else { return }
        let remote = NSImage(systemSymbolName: "appletvremote.gen4.fill", accessibilityDescription: L("Siri Remote"))?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        remote?.isTemplate = true
        button.image = remote
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusDot)
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 5),
            statusDot.heightAnchor.constraint(equalTo: statusDot.widthAnchor),
            statusDot.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 3),
            statusDot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4)
        ])
        refreshStatusDot()
        button.title = ""
        rebuildMenu()
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: "siriRemote", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        if let version = availableUpdateVersion {
            let updateItem = NSMenuItem(
                title: L("Update %@ Available…", version),
                action: #selector(checkForUpdates), keyEquivalent: ""
            )
            updateItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                       accessibilityDescription: nil)
            updateItem.target = self
            menu.addItem(updateItem)
        }

        permissionMenuItem.title = permissionsReady
            ? L("Permissions: Ready ✓") : L("Permissions: Action needed")
        permissionMenuItem.action = permissionsReady ? nil : #selector(openSetup)
        permissionMenuItem.target = permissionsReady ? nil : self
        permissionMenuItem.isEnabled = !permissionsReady
        menu.addItem(permissionMenuItem)

        menu.addItem(.separator())
        let setupItem = NSMenuItem(
            title: L("Open System Check…"), action: #selector(openSetup), keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

        let settingsItem = NSMenuItem(title: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let demoItem = NSMenuItem(
            title: L("Demo Remote"), action: #selector(toggleDemoMode), keyEquivalent: ""
        )
        demoItem.image = NSImage(systemSymbolName: "appletvremote.gen4.fill",
                                 accessibilityDescription: nil)
        demoItem.state = demoRemoteVisible ? .on : .off
        demoItem.target = self
        menu.addItem(demoItem)

        let updatesItem = NSMenuItem(
            title: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func openSetup() { onOpenSetup?() }

    @objc private func checkForUpdates() { onCheckForUpdates?() }

    @objc private func toggleDemoMode() { onToggleDemoMode?() }

    func updateDemoModeVisibility(_ visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.demoRemoteVisible = visible
            self.rebuildMenu()
        }
    }

    func setAvailableUpdate(version: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.availableUpdateVersion = version
            self.statusItem.button?.toolTip = version.map { L("Update %@ Available", $0) }
            self.rebuildMenu()
        }
    }

    func updateConnectionStatus(connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isConnected = connected
            if !connected { self.voiceSources.removeAll() }
            self.refreshStatusDot()
            self.statusMenuItem.title = connected ? L("Status: Connected ✓") : L("Status: Disconnected")
            self.statusItem.button?.appearsDisabled = !connected
        }
    }

    func updatePermissionStatus(ready: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.permissionsReady = ready
            self.refreshStatusDot()
            self.permissionMenuItem.title = ready
                ? L("Permissions: Ready ✓") : L("Permissions: Action needed")
            self.permissionMenuItem.action = ready ? nil : #selector(openSetup)
            self.permissionMenuItem.target = ready ? nil : self
            self.permissionMenuItem.isEnabled = !ready
        }
    }

    @objc private func quitApp() {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(nil)
    }
}
