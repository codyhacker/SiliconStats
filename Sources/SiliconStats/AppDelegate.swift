import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let smc = SMC()
    private let cpuUsage = CPUUsage()
    private var overlayPanel: OverlayPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let smcOpened = smc.open()

        // Prime the CPU usage delta calculation
        _ = cpuUsage.currentUsage()

        buildMenu(smcAvailable: smcOpened)
        updateDisplay()

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    private func buildMenu(smcAvailable: Bool) {
        let menu = NSMenu()

        if !smcAvailable {
            let note = NSMenuItem(title: "⚠ Temp unavailable (run as admin)", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            menu.addItem(.separator())
        }

        let overlayItem = NSMenuItem(title: "Show Overlay", action: #selector(toggleOverlay(_:)), keyEquivalent: "o")
        overlayItem.target = self
        menu.addItem(overlayItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SiliconStats", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        if let panel = overlayPanel, panel.isVisible {
            panel.orderOut(nil)
            sender.title = "Show Overlay"
        } else {
            if overlayPanel == nil {
                overlayPanel = OverlayPanel()
                NotificationCenter.default.addObserver(
                    forName: .overlayDidClose, object: nil, queue: .main
                ) { [weak self] _ in
                    self?.updateOverlayMenuTitle()
                }
            }
            overlayPanel?.orderFrontRegardless()
            sender.title = "Hide Overlay"
        }
    }

    private func updateOverlayMenuTitle() {
        guard let menu = statusItem.menu else { return }
        for item in menu.items where item.action == #selector(toggleOverlay(_:)) {
            item.title = "Show Overlay"
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                sender.state = .off
            } else {
                try service.register()
                sender.state = .on
            }
        } catch {
            NSLog("Failed to toggle launch at login: \(error)")
        }
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func updateDisplay() {
        let usage = cpuUsage.currentUsage()
        let usageStr = String(format: "%.0f%%", usage)

        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }

            let text = NSMutableAttributedString()

            if let temp = self.smc.readCPUTemperature() {
                let tempStr = String(format: "%.0f°", temp)
                if let img = self.symbolImage("thermometer.variable") {
                    let attachment = NSTextAttachment()
                    attachment.image = img
                    text.append(NSAttributedString(attachment: attachment))
                }
                text.append(NSAttributedString(string: " \(tempStr)  "))
            }

            if let img = self.symbolImage("cpu") {
                let attachment = NSTextAttachment()
                attachment.image = img
                text.append(NSAttributedString(attachment: attachment))
            }
            text.append(NSAttributedString(string: " \(usageStr)"))

            button.attributedTitle = text

            if let panel = self.overlayPanel, panel.isVisible {
                panel.update(temp: self.smc.readCPUTemperature(), usage: usage)
            }
        }
    }

    @objc private func quit() {
        smc.close()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        smc.close()
    }
}
