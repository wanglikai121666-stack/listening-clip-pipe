import AppKit

/// 录音会话的置顶悬浮时间轴（屏幕右上角）：
/// 上排是脉冲红点 + REC 计时 + 打标数量，下排是一条代表
/// 「从 0:00 到现在」的全局压缩时间轴，打标区间显示为绿段
/// （未闭合的绿段一直延伸到当前时刻，用半透明绿表示）。
/// 覆盖所有空间和全屏 App，鼠标事件穿透，不抢焦点。
final class RecordingIndicator {
    /// 由 AppDelegate 提供当前打标列表（秒，相对会话开始；end 为 nil 表示未闭合）。
    var marksProvider: (() -> [(start: Double, end: Double?)])?

    private var panel: NSPanel?
    private var timeLabel: NSTextField?
    private var countLabel: NSTextField?
    private var trackLayer: CALayer?
    private var timer: Timer?
    private var startedAt: Date?

    private static let size = NSSize(width: 340, height: 52)
    private static let trackHeight: CGFloat = 8
    private static let trackInsetX: CGFloat = 16

    func show(startedAt: Date = Date()) {
        hide()
        self.startedAt = startedAt

        let size = Self.size
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
        content.layer?.cornerRadius = 12

        // 上排：脉冲红点 + REC 计时 + 打标数
        let dot = CALayer()
        dot.frame = NSRect(x: Self.trackInsetX, y: 31, width: 10, height: 10)
        dot.cornerRadius = 5
        dot.backgroundColor = NSColor.systemRed.cgColor
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.15
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dot.add(pulse, forKey: "pulse")
        content.layer?.addSublayer(dot)

        let time = NSTextField(labelWithString: "REC 0:00")
        time.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        time.textColor = .white
        time.frame = NSRect(x: Self.trackInsetX + 16, y: 27, width: 140, height: 18)
        content.addSubview(time)

        let count = NSTextField(labelWithString: "0 marks")
        count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        count.textColor = NSColor.white.withAlphaComponent(0.8)
        count.alignment = .right
        count.frame = NSRect(
            x: size.width - 140 - Self.trackInsetX, y: 27, width: 140, height: 18
        )
        content.addSubview(count)

        // 下排：全局压缩时间轴（整条 = 从会话开始到现在）
        let track = CALayer()
        track.frame = NSRect(
            x: Self.trackInsetX,
            y: 10,
            width: size.width - Self.trackInsetX * 2,
            height: Self.trackHeight
        )
        track.cornerRadius = Self.trackHeight / 2
        track.masksToBounds = true
        track.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        content.layer?.addSublayer(track)

        panel.contentView = content

        // 主屏右上角，菜单栏正下方。
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: vf.maxX - size.width - 16,
                y: vf.maxY - size.height - 10
            ))
        }
        panel.orderFrontRegardless()

        self.panel = panel
        self.timeLabel = time
        self.countLabel = count
        self.trackLayer = track

        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common 模式：菜单打开、拖动窗口期间计时也不停
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        timeLabel = nil
        countLabel = nil
        trackLayer = nil
        startedAt = nil
    }

    private func tick() {
        guard let startedAt, let timeLabel, let countLabel, let trackLayer else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let secs = Int(elapsed)
        timeLabel.stringValue = String(format: "REC %d:%02d", secs / 60, secs % 60)

        let marks = marksProvider?() ?? []
        countLabel.stringValue = marks.count == 1 ? "1 mark" : "\(marks.count) marks"

        // 重绘绿段：整条 track = [0, elapsed]，按比例映射。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        if elapsed > 0.2 {
            let width = trackLayer.bounds.width
            for mark in marks {
                let startRatio = max(0, mark.start) / elapsed
                let endRatio = min((mark.end ?? elapsed) / elapsed, 1.0)
                guard endRatio > startRatio else { continue }
                let segment = CALayer()
                segment.frame = CGRect(
                    x: CGFloat(startRatio) * width,
                    y: 0,
                    width: max(2, CGFloat(endRatio - startRatio) * width),
                    height: Self.trackHeight
                )
                segment.cornerRadius = Self.trackHeight / 2
                let isOpen = mark.end == nil
                segment.backgroundColor = isOpen
                    ? NSColor.systemGreen.withAlphaComponent(0.55).cgColor
                    : NSColor.systemGreen.cgColor
                trackLayer.addSublayer(segment)
            }
        }
        CATransaction.commit()
    }
}
