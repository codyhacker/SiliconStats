import AppKit
import ServiceManagement

enum Metric: String, CaseIterable {
    case cpuTemp    = "showCPUTemp"
    case gpuTemp    = "showGPUTemp"
    case cpuLoad    = "showCPULoad"
    case gpuLoad    = "showGPULoad"
    case memory     = "showMemory"
    case battery    = "showBattery"

    var label: String {
        switch self {
        case .cpuTemp: return "CPU Temperature"
        case .gpuTemp: return "GPU Temperature"
        case .cpuLoad: return "CPU Load"
        case .gpuLoad: return "GPU Load"
        case .memory:  return "Memory Usage"
        case .battery: return "Battery"
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .cpuTemp, .cpuLoad: return true
        case .gpuTemp, .gpuLoad, .memory, .battery: return false
        }
    }

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: rawValue) == nil {
                return defaultEnabled
            }
            return UserDefaults.standard.bool(forKey: rawValue)
        }
        set { UserDefaults.standard.set(newValue, forKey: rawValue) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let smc = SMC()
    private let cpuUsage = CPUUsage()
    private let gpuMonitor = GPUMonitor()
    private let batteryMonitor = BatteryMonitor()
    private let memoryMonitor = MemoryMonitor()
    private var overlayPanel: OverlayPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let smcOpened = smc.open()

        _ = cpuUsage.currentUsage()

        buildMenu(smcAvailable: smcOpened)
        updateDisplay()

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    // MARK: - Menu

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

        menu.addItem(.separator())

        let header = NSMenuItem(title: "Metrics", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for metric in Metric.allCases {
            let item = NSMenuItem(title: metric.label, action: #selector(toggleMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = metric
            item.state = metric.isEnabled ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SiliconStats", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let metric = sender.representedObject as? Metric else { return }
        var m = metric
        m.isEnabled = !metric.isEnabled
        sender.state = m.isEnabled ? .on : .off
        updateDisplay()
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

    // MARK: - Display

    private func symbolImage(_ name: String, size: CGFloat = 12) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func ringImage(percentage: Double, diameter: CGFloat, lineWidth: CGFloat = 1.5, label: String? = nil) -> NSImage {
        let img = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let inset = lineWidth / 2 + 0.5
            let ringRect = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = min(ringRect.width, ringRect.height) / 2

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.15).setStroke()
            track.stroke()

            let clamped = min(max(percentage, 0), 100)
            if clamped > 0 {
                let startAngle: CGFloat = 90
                let endAngle = 90 - (clamped / 100.0 * 360.0)
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.labelColor.withAlphaComponent(0.8).setStroke()
                arc.stroke()
            }

            if let label {
                let fontSize = diameter * 0.32
                let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(0.6),
                ]
                let str = NSAttributedString(string: label, attributes: attrs)
                let strSize = str.size()
                str.draw(at: NSPoint(x: center.x - strSize.width / 2, y: center.y - strSize.height / 2))
            }

            return true
        }
        img.isTemplate = false
        return img
    }

    private struct Stats {
        var cpuTemp: Double?
        var gpuTemp: Double?
        var cpuLoad: Double?
        var gpuLoad: Double?
        var memory: MemoryState?
        var battery: BatteryState?
    }

    private func gatherStats() -> Stats {
        var s = Stats()
        if Metric.cpuTemp.isEnabled { s.cpuTemp = smc.readCPUTemperature() }
        if Metric.gpuTemp.isEnabled { s.gpuTemp = smc.readGPUTemperature() }
        if Metric.cpuLoad.isEnabled { s.cpuLoad = cpuUsage.currentUsage() }
        if Metric.gpuLoad.isEnabled { s.gpuLoad = gpuMonitor.currentUtilization() }
        if Metric.memory.isEnabled  { s.memory = memoryMonitor.currentState() }
        if Metric.battery.isEnabled { s.battery = batteryMonitor.currentState() }
        return s
    }

    private func makeRingAttachment(percentage: Double, label: String, fontSize: CGFloat) -> NSTextAttachment {
        let diameter = fontSize
        let ring = ringImage(percentage: percentage, diameter: diameter, lineWidth: 1.5, label: label)
        let a = NSTextAttachment()
        a.image = ring
        let yOffset = (fontSize - diameter) / 2 - 1
        a.bounds = NSRect(x: 0, y: yOffset, width: diameter, height: diameter)
        return a
    }

    private func buildAttributedString(stats: Stats, fontSize: CGFloat = 12) -> NSAttributedString {
        let text = NSMutableAttributedString()
        var segments: [NSAttributedString] = []
        let mono = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)

        if let temp = stats.cpuTemp {
            let seg = NSMutableAttributedString()
            if let img = symbolImage("thermometer.and.ellipsis", size: fontSize) {
                let a = NSTextAttachment(); a.image = img
                seg.append(NSAttributedString(attachment: a))
            }
            seg.append(NSAttributedString(string: String(format: " %3.0f°", temp), attributes: [.font: mono]))
            segments.append(seg)
        }

        if let temp = stats.gpuTemp {
            let seg = NSMutableAttributedString()
            if let img = symbolImage("gpu", size: fontSize) {
                let a = NSTextAttachment(); a.image = img
                seg.append(NSAttributedString(attachment: a))
            }
            seg.append(NSAttributedString(string: String(format: " %3.0f°", temp), attributes: [.font: mono]))
            segments.append(seg)
        }

        if let load = stats.cpuLoad {
            let seg = NSMutableAttributedString()
            seg.append(NSAttributedString(attachment: makeRingAttachment(percentage: load, label: "C", fontSize: fontSize)))
            seg.append(NSAttributedString(string: String(format: " %3.0f%%", load), attributes: [.font: mono]))
            segments.append(seg)
        }

        if let load = stats.gpuLoad {
            let seg = NSMutableAttributedString()
            seg.append(NSAttributedString(attachment: makeRingAttachment(percentage: load, label: "G", fontSize: fontSize)))
            seg.append(NSAttributedString(string: String(format: " %3.0f%%", load), attributes: [.font: mono]))
            segments.append(seg)
        }

        if let mem = stats.memory {
            let seg = NSMutableAttributedString()
            if let img = symbolImage("memorychip", size: fontSize) {
                let a = NSTextAttachment(); a.image = img
                seg.append(NSAttributedString(attachment: a))
            }
            seg.append(NSAttributedString(string: String(format: " %4.1f/%2.0fGB", mem.usedGB, mem.totalGB), attributes: [.font: mono]))
            segments.append(seg)
        }

        if let bat = stats.battery {
            let seg = NSMutableAttributedString()
            let iconName = bat.isCharging ? "battery.100percent.bolt" : "battery.100percent"
            if let img = symbolImage(iconName, size: fontSize) {
                let a = NSTextAttachment(); a.image = img
                seg.append(NSAttributedString(attachment: a))
            }
            seg.append(NSAttributedString(string: String(format: " %3d%%", bat.percentage), attributes: [.font: mono]))
            segments.append(seg)
        }

        for (i, seg) in segments.enumerated() {
            if i > 0 { text.append(NSAttributedString(string: "  ")) }
            text.append(seg)
        }

        return text
    }

    private func updateDisplay() {
        let stats = gatherStats()

        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            button.attributedTitle = self.buildAttributedString(stats: stats)

            if let panel = self.overlayPanel, panel.isVisible {
                panel.update(content: self.buildAttributedString(stats: stats, fontSize: 11))
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
