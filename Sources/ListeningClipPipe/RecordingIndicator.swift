import AppKit

/// 录音时屏幕右上角的置顶悬浮指示器：脉冲红点 + REC 计时。
/// 覆盖所有空间和全屏 App，鼠标事件穿透，不抢焦点。
final class RecordingIndicator {
    private var panel: NSPanel?
    private var timeLabel: NSTextField?
    private var timer: Timer?
    private var startedAt: Date?

    func show() {
        hide()
        startedAt = Date()

        let size = NSSize(width: 136, height: 36)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        content.layer?.cornerRadius = size.height / 2

        let dot = CALayer()
        dot.frame = NSRect(x: 14, y: (size.height - 12) / 2, width: 12, height: 12)
        dot.cornerRadius = 6
        dot.backgroundColor = NSColor.systemRed.cgColor
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.15
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dot.add(pulse, forKey: "pulse")
        content.layer?.addSublayer(dot)

        let label = NSTextField(labelWithString: "REC 0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.frame = NSRect(x: 36, y: 8, width: size.width - 42, height: 20)
        content.addSubview(label)

        panel.contentView = content

        // 主屏右上角，菜单栏正下方。
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let origin = NSPoint(
                x: vf.maxX - size.width - 16,
                y: vf.maxY - size.height - 10
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()

        self.panel = panel
        self.timeLabel = label

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common 模式：菜单打开、拖动窗口期间计时也不停
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        timeLabel = nil
        startedAt = nil
    }

    private func tick() {
        guard let startedAt, let timeLabel else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        timeLabel.stringValue = String(format: "REC %d:%02d", elapsed / 60, elapsed % 60)
    }
}
