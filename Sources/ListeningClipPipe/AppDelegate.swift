import AppKit
import Carbon.HIToolbox
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = RecorderService()
    private let clipboard = ClipboardService()
    private let hotkey = HotkeyManager()
    private let indicator = RecordingIndicator()
    private var store: ClipStore!

    /// 会话模型：⌥Z 开始/结束一次总录音；录音期间空格被系统级独占，
    /// 负责打标——第一下开一个绿段，第二下闭合，可打任意多段。
    private var spaceHotkeyID: UInt32?
    /// 打标区间（秒，相对会话开始；end 为 nil 表示未闭合）。
    private var marks: [(start: Double, end: Double?)] = []

    private var currentClipID: String?
    private var recordingStartedAt: Date?
    private var lastMeta: ClipMetadata?

    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var markMenuItem: NSMenuItem!
    private var prerollMenuItem: NSMenuItem!
    private var indicatorMenuItem: NSMenuItem!
    private var copyBothMenuItem: NSMenuItem!
    private var copyClipMenuItem: NSMenuItem!
    private var copyAnchorMenuItem: NSMenuItem!

    private static let indicatorDefaultsKey = "ShowRecIndicator"
    /// 屏幕悬浮时间轴开关（菜单里可切换，默认开启）。
    private var showIndicator: Bool {
        get { UserDefaults.standard.object(forKey: Self.indicatorDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.indicatorDefaultsKey) }
    }

    private static let prerollDefaultsKey = "MarkPrerollSeconds"
    private static let prerollChoices: [Double] = [0, 0.1, 0.2, 0.3, 0.5, 1.0]
    /// 打标提前量：按空格开标的时刻 t，绿段实际从 t - preroll 开始，
    /// 刻画「听了一半才意识到没听懂」。默认 0.3s。
    private var prerollSeconds: Double {
        get { UserDefaults.standard.object(forKey: Self.prerollDefaultsKey) as? Double ?? 0.3 }
        set { UserDefaults.standard.set(newValue, forKey: Self.prerollDefaultsKey) }
    }

    /// 只有以 .app bundle 运行时才有 bundle id，才能用系统通知；
    /// swift run 裸跑可执行文件时降级为提示音。
    private let notificationsAvailable = Bundle.main.bundleIdentifier != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try ClipStore()
        } catch {
            fatalStartupAlert("无法创建本地存储目录 ~/Documents/ListeningClipPipe", error)
            return
        }
        lastMeta = store.lastClip()

        indicator.marksProvider = { [weak self] in self?.marks ?? [] }

        setupStatusItem()

        do {
            try hotkey.register(keyCode: kVK_ANSI_Z, modifiers: optionKey) { [weak self] in
                self?.toggleSession()
            }
        } catch {
            showError("注册全局快捷键 ⌥Z 失败", error)
        }

        if notificationsAvailable {
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recorder.isRecording {
            stopSession()
        }
        indicator.hide()
        hotkey.unregisterAll()
    }

    // MARK: - 会话

    @objc func toggleSession() {
        if recorder.isRecording {
            stopSession()
        } else {
            startSession()
        }
        refreshUI()
    }

    private func startSession() {
        let startedAt = Date()
        let id = store.makeClipID(date: startedAt)
        do {
            try recorder.start(writingTo: store.audioURL(for: id))
        } catch {
            showError("开始录制失败", error)
            return
        }
        currentClipID = id
        recordingStartedAt = startedAt
        marks = []

        // 录音期间空格被独占，负责打标；结束后立即归还。
        do {
            spaceHotkeyID = try hotkey.register(keyCode: kVK_Space, modifiers: 0) { [weak self] in
                self?.toggleMark()
            }
        } catch {
            showError("占用空格键失败（打标不可用，录音继续）", error)
        }

        if showIndicator {
            indicator.show(startedAt: startedAt)
        }
        NSSound(named: "Pop")?.play()
    }

    private func stopSession() {
        guard let id = currentClipID, let startedAt = recordingStartedAt else { return }
        currentClipID = nil
        recordingStartedAt = nil
        if let spaceID = spaceHotkeyID {
            hotkey.unregister(id: spaceID)
            spaceHotkeyID = nil
        }
        indicator.hide()

        do {
            let duration = try recorder.stop()

            // 最后一个绿段未闭合的话，以停止时刻为其结束。
            var ranges: [(start: Double, end: Double)] = marks.compactMap { mark in
                let end = min(mark.end ?? duration, duration)
                let start = max(0, min(mark.start, duration))
                return end - start > 0.05 ? (start, end) : nil
            }
            ranges.sort { $0.start < $1.start }
            marks = []

            // 有打标时总录音改名为「_总录音」，粘贴到飞书后和切分段一眼可辨。
            var fullURL = store.audioURL(for: id)
            if !ranges.isEmpty {
                let renamedURL = store.fullRecordingURL(for: id)
                try FileManager.default.moveItem(at: fullURL, to: renamedURL)
                fullURL = renamedURL
            }

            // 按绿段切割片段文件：LC_xxx_第1段切分.wav …
            var segments: [ClipSegment] = []
            for (index, range) in ranges.enumerated() {
                let segURL = store.segmentURL(for: id, index: index + 1)
                try AudioSlicer.slice(source: fullURL, to: segURL, start: range.start, end: range.end)
                segments.append(ClipSegment(
                    file: segURL.lastPathComponent,
                    start_sec: (range.start * 10).rounded() / 10,
                    end_sec: (range.end * 10).rounded() / 10,
                    duration_sec: ((range.end - range.start) * 10).rounded() / 10
                ))
            }

            let meta = store.makeMetadata(
                id: id,
                startedAt: startedAt,
                duration: duration,
                audioFile: fullURL.lastPathComponent,
                segments: segments.isEmpty ? nil : segments
            )
            try store.save(meta)
            lastMeta = meta

            if segments.isEmpty {
                // 没打标：和原来一样，粘贴出来就是完整一条。
                clipboard.copyComposite(fileURL: fullURL, anchor: store.anchorText(for: meta))
                notify(
                    title: "Clip copied",
                    body: "\(id)（\(meta.duration_sec)s）已复制，切到飞书 Cmd+V 粘贴。"
                )
            } else {
                // 打了标：总录音 + 全部绿段片段一起进剪贴板。
                let urls = [fullURL] + segments.map { store.clipsDir.appendingPathComponent($0.file) }
                clipboard.copyFiles(urls)
                notify(
                    title: "Session copied",
                    body: "总录音 \(meta.duration_sec)s + \(segments.count) 个打标片段已复制，Cmd+V 全部粘出。"
                )
            }
        } catch {
            marks = []
            showError("停止录制失败", error)
        }
        refreshUI()
    }

    // MARK: - 打标

    @objc private func toggleMark() {
        guard recorder.isRecording, let startedAt = recordingStartedAt else { return }
        let now = Date().timeIntervalSince(startedAt)
        if let last = marks.indices.last, marks[last].end == nil {
            // 闭合当前绿段
            marks[last].end = now
            NSSound(named: "Morse")?.play()
        } else {
            // 开新绿段（带提前量，刻画「听了一半才意识到没听懂」）
            marks.append((start: max(0, now - prerollSeconds), end: nil))
            NSSound(named: "Tink")?.play()
        }
        refreshUI()
    }

    @objc private func selectPreroll(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double {
            prerollSeconds = value
        }
        refreshUI()
    }

    // MARK: - 菜单动作

    @objc private func toggleIndicatorSetting() {
        showIndicator.toggle()
        if recorder.isRecording {
            if showIndicator, let startedAt = recordingStartedAt {
                indicator.show(startedAt: startedAt)
            } else {
                indicator.hide()
            }
        }
        refreshUI()
    }

    @objc private func copyLastComposite() {
        guard let meta = lastMeta else { return }
        clipboard.copyComposite(
            fileURL: store.fileURL(for: meta),
            anchor: store.anchorText(for: meta)
        )
        notify(title: "Clip + anchor copied", body: meta.id)
    }

    @objc private func copyLastClip() {
        guard let meta = lastMeta else { return }
        if let segments = meta.segments, !segments.isEmpty {
            let urls = [store.fileURL(for: meta)]
                + segments.map { store.clipsDir.appendingPathComponent($0.file) }
            clipboard.copyFiles(urls)
            notify(title: "Session copied", body: "\(meta.id) + \(segments.count) 个片段")
        } else {
            clipboard.copyAudioFile(store.fileURL(for: meta))
            notify(title: "Clip copied", body: meta.id)
        }
    }

    @objc private func copyLastAnchor() {
        guard let meta = lastMeta else { return }
        clipboard.copyAnchor(store.anchorText(for: meta))
        notify(title: "Anchor copied", body: meta.paste_anchor)
    }

    @objc private func openClipsFolder() {
        NSWorkspace.shared.open(store.clipsDir)
    }

    // MARK: - UI

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false

        toggleMenuItem = menuItem("Start Recording", #selector(toggleSession), key: "z", modifiers: [.option])
        markMenuItem = menuItem("Mark (Space)", #selector(toggleMark))

        prerollMenuItem = NSMenuItem(title: "Mark Pre-roll", action: nil, keyEquivalent: "")
        let prerollMenu = NSMenu()
        for value in Self.prerollChoices {
            let title = value == 0 ? "Off" : String(format: "%.1fs", value)
            let item = NSMenuItem(title: title, action: #selector(selectPreroll(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            prerollMenu.addItem(item)
        }
        prerollMenuItem.submenu = prerollMenu

        indicatorMenuItem = menuItem("Show On-Screen Timeline", #selector(toggleIndicatorSetting))
        copyBothMenuItem = menuItem("Copy Last Clip + Anchor", #selector(copyLastComposite))
        copyClipMenuItem = menuItem("Copy Last Clip", #selector(copyLastClip))
        copyAnchorMenuItem = menuItem("Copy Last Anchor", #selector(copyLastAnchor))
        let openItem = menuItem("Open Clips Folder", #selector(openClipsFolder))
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.items = [
            statusMenuItem,
            .separator(),
            toggleMenuItem,
            markMenuItem,
            .separator(),
            copyBothMenuItem,
            copyClipMenuItem,
            copyAnchorMenuItem,
            .separator(),
            prerollMenuItem,
            indicatorMenuItem,
            openItem,
            .separator(),
            quitItem,
        ]
        statusItem.menu = menu
    }

    private func menuItem(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func refreshUI() {
        let recording = recorder.isRecording

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: recording ? "record.circle.fill" : "waveform.circle",
                accessibilityDescription: "Listening Clip Pipe"
            )
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = recording ? .systemRed : nil
            button.toolTip = recording
                ? "Recording…（空格打标，⌥Z 停止）"
                : "Listening Clip Pipe（⌥Z 开始录制）"
        }

        if recording {
            let open = marks.last?.end == nil && !marks.isEmpty
            statusMenuItem.title = open
                ? "● Recording… \(marks.count) 标记（空格闭合绿段）"
                : "● Recording… \(marks.count) 标记（空格开始打标）"
        } else {
            statusMenuItem.title = lastMeta.map { "Idle · last: \($0.id)" } ?? "Idle"
        }

        toggleMenuItem.title = recording ? "Stop Recording" : "Start Recording"
        markMenuItem.isEnabled = recording
        indicatorMenuItem.state = showIndicator ? .on : .off

        if let prerollMenu = prerollMenuItem.submenu {
            for item in prerollMenu.items {
                let value = item.representedObject as? Double ?? -1
                item.state = abs(value - prerollSeconds) < 0.001 ? .on : .off
            }
        }

        let hasLast = lastMeta != nil
        copyBothMenuItem.isEnabled = hasLast
        copyClipMenuItem.isEnabled = hasLast
        copyAnchorMenuItem.isEnabled = hasLast
    }

    // MARK: - 通知与报错

    private func notify(title: String, body: String) {
        guard notificationsAvailable else {
            NSSound(named: "Glass")?.play()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 录制失败必须显式报错（PRD 验收标准 12），不允许静默失败。
    private func showError(_ title: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func fatalStartupAlert(_ title: String, _ error: Error) {
        showError(title, error)
        NSApp.terminate(nil)
    }
}
