import Carbon.HIToolbox
import Foundation

/// 全局快捷键 Option + Z。
/// 使用 Carbon RegisterEventHotKey，不需要辅助功能/输入监控权限。
final class HotkeyManager {
    enum HotkeyError: LocalizedError {
        case installHandlerFailed(OSStatus)
        case registerFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installHandlerFailed(let status):
                return "安装快捷键事件处理器失败（OSStatus \(status)）。"
            case .registerFailed(let status):
                return "注册全局快捷键 ⌥Z 失败（OSStatus \(status)），可能与其他 App 的快捷键冲突。"
            }
        }
    }

    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onHotkey?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        guard status == noErr else { throw HotkeyError.installHandlerFailed(status) }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C43_5031), id: 1) // 'LCP1'
        status = RegisterEventHotKey(
            UInt32(kVK_ANSI_Z),
            UInt32(optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { throw HotkeyError.registerFailed(status) }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
