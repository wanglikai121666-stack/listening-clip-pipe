import AVFoundation
import Foundation

/// 从总录音 WAV 里按时间区间切出片段文件。
enum AudioSlicer {
    enum SliceError: LocalizedError {
        case emptyRange
        case bufferAllocation

        var errorDescription: String? {
            switch self {
            case .emptyRange: return "打标区间为空，无法切割。"
            case .bufferAllocation: return "音频缓冲区分配失败。"
            }
        }
    }

    /// 把 source 的 [start, end]（秒）切到 dest（与源相同的格式设置）。
    static func slice(source: URL, to dest: URL, start: Double, end: Double) throws {
        let src = try AVAudioFile(forReading: source)
        let sampleRate = src.processingFormat.sampleRate
        var startFrame = AVAudioFramePosition(max(0, start) * sampleRate)
        var endFrame = AVAudioFramePosition(end * sampleRate)
        startFrame = min(startFrame, src.length)
        endFrame = min(endFrame, src.length)
        guard endFrame > startFrame else { throw SliceError.emptyRange }

        let dst = try AVAudioFile(forWriting: dest, settings: src.fileFormat.settings)
        src.framePosition = startFrame

        var remaining = AVAudioFrameCount(endFrame - startFrame)
        let chunkSize: AVAudioFrameCount = 65536
        while remaining > 0 {
            let n = min(chunkSize, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: src.processingFormat, frameCapacity: n) else {
                throw SliceError.bufferAllocation
            }
            try src.read(into: buffer, frameCount: n)
            if buffer.frameLength == 0 { break }
            try dst.write(from: buffer)
            remaining -= buffer.frameLength
        }
    }
}
