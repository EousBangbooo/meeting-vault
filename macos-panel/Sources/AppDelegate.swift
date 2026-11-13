import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var initialVaultPath: String?
    var testReportURL: URL?

    private let model = PanelModel()
    private let reader = VaultReader()
    private let scanQueue = DispatchQueue(label: "meeting-vault-panel.scan", qos: .utility)
    private var watcher: VaultWatcher?
    private var panelController: PanelController!
    private var statusItem: NSStatusItem!
    private var vaultURL: URL?
    private var scopedURL: URL?
    private var scanInFlight = false
    private var vaultGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController(model: model)
        panelController.onOpenDetail = { url in NSWorkspace.shared.open(url) }
        panelController.onDidChange = { [weak self] in self?.updateStatusItem() }

        setUpStatusItem()
        panelController.show()
        updateStatusItem()

        if let initialVaultPath, !initialVaultPath.isEmpty {
            setVault(URL(fileURLWithPath: initialVaultPath).standardizedFileURL)
        }
        writeTestReport()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        watcher = nil
        stopSecurityScope()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MV …"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.toolTip = "Meeting Vault 常驻看板（原型）"

        let menu = NSMenu()
        menu.addItem(menuItem("恢复浮窗", action: #selector(showPanel), key: "o"))
        menu.addItem(menuItem("立即刷新", action: #selector(refreshFromMenu), key: "r"))
        menu.addItem(.separator())
        menu.addItem(menuItem("切换置顶", action: #selector(togglePin), key: ""))
        menu.addItem(menuItem("选择会议库…", action: #selector(chooseVaultFromMenu), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 Meeting Vault", action: #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateStatusItem() {
        statusItem?.button?.title = model.menuTitle
    }

    @objc private func showPanel() {
        panelController.show()
    }

    @objc private func refreshFromMenu() {
        scanNow()
    }

    @objc private func togglePin() {
        panelController.togglePin()
    }

    @objc private func chooseVaultFromMenu() {
        chooseVault()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func chooseVault() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = false
        openPanel.prompt = "选择会议库"
        openPanel.message = "选择包含 inbox 与 .meeting-review 的会议库目录（只读）"
        NSApp.activate(ignoringOtherApps: true)
        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            self?.setVault(url.standardizedFileURL)
        }
    }

    private func setVault(_ url: URL) {
        watcher?.stop()
        stopSecurityScope()
        vaultURL = url
        vaultGeneration += 1
        scopedURL = url
        if !url.startAccessingSecurityScopedResource() {
            // 非沙盒或命令行 --vault 通常返回 false；不代表无权限。
            scopedURL = nil
        }
        model.beginVault()
        panelController.refreshNow()
        updateStatusItem()

        let watcher = VaultWatcher()
        watcher.onNeedsScan = { [weak self] in
            DispatchQueue.main.async { self?.scanNow() }
        }
        watcher.start(vaultURL: url)
        self.watcher = watcher
        scanNow()
    }

    private func stopSecurityScope() {
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
    }

    private func scanNow() {
        guard let vaultURL, !scanInFlight else { return }
        let generation = vaultGeneration
        scanInFlight = true
        scanQueue.async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.reader.scan(vaultURL: vaultURL)
                DispatchQueue.main.async {
                    self.scanInFlight = false
                    guard generation == self.vaultGeneration else { self.scanNow(); return }
                    self.model.apply(snapshot)
                    self.panelController.render()
                    self.writeTestReport()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                FileHandle.standardError.write(Data("[scan] \(message)\n".utf8))
                DispatchQueue.main.async {
                    self.scanInFlight = false
                    guard generation == self.vaultGeneration else { self.scanNow(); return }
                    self.model.applyFailure(message)
                    self.panelController.render()
                    self.writeTestReport()
                }
            }
        }
    }

    private func writeTestReport() {
        guard let testReportURL else { return }
        let panel = panelController.panel
        let report: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "time": Date().timeIntervalSince1970,
            "screenCount": NSScreen.screens.count,
            "visible": panel.isVisible,
            "windowNumber": panel.windowNumber,
            "intersectsScreen": NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) },
            "key": panel.isKeyWindow,
            "floating": panel.level == .floating,
            "countsLabel": panelController.displayedCounts,
            "secondaryLabel": panelController.displayedSecondary,
            "stripLabel": panelController.displayedStrip,
            "panelHeight": panel.frame.height,
            "menuLabel": statusItem.button?.title ?? "",
            "stale": model.isStale
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            try data.write(to: testReportURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[test] unable to write report\n".utf8))
        }
    }
}
