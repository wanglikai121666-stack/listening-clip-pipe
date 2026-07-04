import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// 系统音频录制。
///
/// 实现方式：Core Audio Process Tap（macOS 14.4+）。
/// - 对全部系统输出创建一个全局 tap（不含麦克风）。
/// - 建一个私有 aggregate device 把 tap 挂上去，用 IOProc 拉 PCM 流。
/// - 实时写入 16-bit PCM WAV 文件（兼容性最好，方便直接拖入/粘贴到飞书）。
///
/// 权限：首次使用会触发「系统设置 → 隐私与安全性 → 屏幕与系统音频录制 → 仅录制系统音频」
/// 的授权弹窗（NSAudioCaptureUsageDescription）。不需要麦克风、屏幕录制、辅助功能权限。
enum RecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case coreAudio(String, OSStatus)
    case fileCreation(Error)
    case fileWrite(Error)
    case noFormat

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "已经在录制中。"
        case .notRecording:
            return "当前没有在录制。"
        case .coreAudio(let step, let status):
            return "系统音频捕获失败（\(step)，OSStatus \(status)）。"
                + "请到「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中允许 ListeningClipPipe 录制系统音频后重试。"
        case .fileCreation(let err):
            return "创建音频文件失败：\(err.localizedDescription)"
        case .fileWrite(let err):
            return "写入音频数据失败：\(err.localizedDescription)"
        case .noFormat:
            return "无法读取系统音频流格式。"
        }
    }
}

final class RecorderService {
    private(set) var isRecording = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var firstWriteError: Error?
    private let ioQueue = DispatchQueue(label: "com.likai.listeningclippipe.io")

    /// 开始录制系统音频，实时写入 url 指向的 wav 文件。
    func start(writingTo url: URL) throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        firstWriteError = nil
        do {
            try startTap(url: url)
        } catch {
            teardownCoreAudio()
            ioQueue.sync { self.file = nil }
            throw error
        }
        isRecording = true
    }

    /// 停止录制，返回时长（秒）。
    @discardableResult
    func stop() throws -> Double {
        guard isRecording else { throw RecorderError.notRecording }
        isRecording = false

        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
        }
        teardownCoreAudio()

        var duration = 0.0
        ioQueue.sync {
            if let file = self.file {
                duration = Double(file.length) / file.fileFormat.sampleRate
            }
            self.file = nil // 关闭文件（AVAudioFile 在释放时写入 header）
        }

        if duration == 0, let err = firstWriteError {
            throw RecorderError.fileWrite(err)
        }
        return duration
    }

    // MARK: - Core Audio

    private func startTap(url: URL) throws {
        // 1. 创建全局系统音频 tap（排除进程列表为空 = 录全部进程的输出）。
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.uuid = UUID()
        tapDesc.name = "ListeningClipPipe Tap"
        tapDesc.muteBehavior = .unmuted
        tapDesc.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            throw RecorderError.coreAudio("创建系统音频 tap", status)
        }
        tapID = newTapID

        // 2. 读取 tap 的流格式。
        var streamDesc = AudioStreamBasicDescription()
        var descSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        status = AudioObjectGetPropertyData(tapID, &formatAddr, 0, nil, &descSize, &streamDesc)
        guard status == noErr else {
            throw RecorderError.coreAudio("读取 tap 音频格式", status)
        }
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else {
            throw RecorderError.noFormat
        }

        // 3. 用「默认输出设备 + tap」建一个私有 aggregate device。
        let outputUID = try defaultOutputDeviceUID()
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ListeningClipPipe",
            kAudioAggregateDeviceUIDKey: "com.likai.listeningclippipe.aggregate",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDesc.uuid.uuidString,
                ]
            ],
        ]
        var newAggID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard status == noErr, newAggID != kAudioObjectUnknown else {
            throw RecorderError.coreAudio("创建聚合音频设备", status)
        }
        aggregateID = newAggID

        // 4. 打开输出文件：16-bit PCM WAV（写入时由 AVAudioFile 从 float32 自动转换）。
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: streamDesc.mSampleRate,
            AVNumberOfChannelsKey: Int(streamDesc.mChannelsPerFrame),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: format.isInterleaved
            )
        } catch {
            throw RecorderError.fileCreation(error)
        }

        // 5. IOProc：把 tap 输入的 PCM 持续写入文件。
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self, let file = self.file else { return }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else { return }
            do {
                try file.write(from: buffer)
            } catch {
                if self.firstWriteError == nil { self.firstWriteError = error }
            }
        }
        guard status == noErr, ioProcID != nil else {
            throw RecorderError.coreAudio("创建 IO proc", status)
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            throw RecorderError.coreAudio("启动音频设备", status)
        }
    }

    private func teardownCoreAudio() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
                self.ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw RecorderError.coreAudio("查找默认输出设备", status)
        }

        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &uidSize, ptr)
        }
        guard status == noErr else {
            throw RecorderError.coreAudio("读取输出设备 UID", status)
        }
        return uid as String
    }
}
