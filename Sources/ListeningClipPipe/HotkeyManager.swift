import Carbon.HIToolbox
import Foundation

/// 全局热键管理（Carbon RegisterEventHotKey，不需要辅助功能/输入监控权限）。
///
/// 支持动态注册/注销多个热键。注册无修饰键的普通键（如空格）时，
/// 该键会被系统级独占——其他 App 收不到按键，注销后立即恢复，
/// 这正是「捕获模式」占用空格的实现方式。
final class HotkeyManager {
    enum HotkeyError: LocalizedError {
        case installHandlerFailed(OSStatus)
        case registerFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installHandlerFailed(let status):
                return "安装快捷键事件处理器失败（OSStatus \(status)）。"
            case .registerFailed(let status):
                return "注册全局快捷键失败（OSStatus \(status)），可能与其他 App 的快捷键冲突。"
            }
        }
    }

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeys: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var nextID: UInt32 = 1

    /// 注册一个全局热键，返回句柄 ID（用于注销）。modifiers 传 0 表示无修饰键。
    @discardableResult
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) throws -> UInt32 {
        try installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C43_5031), id: id) // 'LCP1'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { throw HotkeyError.registerFailed(status) }
        hotkeys[id] = (ref, action)
        return id
    }

    func unregister(id: UInt32) {
        if let entry = hotkeys.removeValue(forKey: id) {
            UnregisterEventHotKey(entry.ref)
        }
    }

    func unregisterAll() {
        for id in Array(hotkeys.keys) {
            unregister(id: id)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    fileprivate func dispatch(id: UInt32) {
        hotkeys[id]?.action()
    }

    private func installHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    manager.dispatch(id: id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        guard status == noErr else { throw HotkeyError.installHandlerFailed(status) }
    }

    deinit {
        unregisterAll()
    }
}
