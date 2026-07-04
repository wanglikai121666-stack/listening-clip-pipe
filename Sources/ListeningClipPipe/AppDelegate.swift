import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = RecorderService()
    private let clipboard = ClipboardService()
    private let hotkey = HotkeyManager()
    private let indicator = RecordingIndicator()
    private var store: ClipStore!

    private var currentClipID: String?
    private var recordingStartedAt: Date?
    private var lastMeta: ClipMetadata?

    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var copyBothMenuItem: NSMenuItem!
    private var copyClipMenuItem: NSMenuItem!
    private var copyAnchorMenuItem: NSMenuItem!

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

        setupStatusItem()

        hotkey.onHotkey = { [weak self] in self?.toggleRecording() }
        do {
            try hotkey.register()
        } catch {
            showError("注册全局快捷键失败", error)
        }

        if notificationsAvailable {
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recorder.isRecording {
            _ = try? recorder.stop()
        }
        indicator.hide()
        hotkey.unregister()
    }

    // MARK: - 录制

    @objc func toggleRecording() {
        if recorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let startedAt = Date()
        let id = store.makeClipID(date: startedAt)
        do {
            try recorder.start(writingTo: store.audioURL(for: id))
            currentClipID = id
            recordingStartedAt = startedAt
            indicator.show()
            NSSound(named: "Pop")?.play()
        } catch {
            showError("开始录制失败", error)
        }
        refreshUI()
    }

    private func stopRecording() {
        guard let id = currentClipID, let startedAt = recordingStartedAt else { return }
        currentClipID = nil
        recordingStartedAt = nil
        indicator.hide()
        do {
            let duration = try recorder.stop()
            let meta = store.makeMetadata(id: id, startedAt: startedAt, duration: duration)
            try store.save(meta)
            lastMeta = meta
            clipboard.copyComposite(
                fileURL: store.audioURL(for: id),
                anchor: store.anchorText(for: meta)
            )
            notify(
                title: "Clip copied",
                body: "\(id)（\(meta.duration_sec)s）已复制，切到飞书 Cmd+V 粘贴。"
            )
        } catch {
            showError("停止录制失败", error)
        }
        refreshUI()
    }

    // MARK: - 菜单动作

    @objc private func copyLastComposite() {
        guard let meta = lastMeta else { return }
        clipboard.copyComposite(
            fileURL: store.audioURL(for: meta.id),
            anchor: store.anchorText(for: meta)
        )
        notify(title: "Clip + anchor copied", body: meta.id)
    }

    @objc private func copyLastClip() {
        guard let meta = lastMeta else { return }
        clipboard.copyAudioFile(store.audioURL(for: meta.id))
        notify(title: "Clip copied", body: meta.id)
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

        toggleMenuItem = menuItem("Start Recording", #selector(toggleRecording), key: "z", modifiers: [.option])
        copyBothMenuItem = menuItem("Copy Last Clip + Anchor", #selector(copyLastComposite))
        copyClipMenuItem = menuItem("Copy Last Clip", #selector(copyLastClip))
        copyAnchorMenuItem = menuItem("Copy Last Anchor", #selector(copyLastAnchor))
        let openItem = menuItem("Open Clips Folder", #selector(openClipsFolder))
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.items = [
            statusMenuItem,
            .separator(),
            toggleMenuItem,
            .separator(),
            copyBothMenuItem,
            copyClipMenuItem,
            copyAnchorMenuItem,
            .separator(),
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
            let symbolName = recording ? "record.circle.fill" : "waveform.circle"
            let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "Listening Clip Pipe"
            )
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = recording ? .systemRed : nil
            button.toolTip = recording ? "Recording…（⌥Z 停止）" : "Listening Clip Pipe（⌥Z 开始录制）"
        }

        statusMenuItem.title = recording
            ? "● Recording…（⌥Z 停止）"
            : (lastMeta.map { "Idle · last: \($0.id)" } ?? "Idle")
        toggleMenuItem.title = recording ? "Stop Recording" : "Start Recording"

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
