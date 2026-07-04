import Foundation

/// 每段 clip 的元数据，对应 PRD 第 12 节的 metadata.json 结构。
struct ClipMetadata: Codable {
    var id: String
    var created_at: String
    var duration_sec: Double
    var source: String
    var audio_file: String
    var local_path: String
    var paste_anchor: String
    var tags: [String]
    var note: String
    var feishu_doc_url: String
    var feishu_block_id: String
    var feishu_file_token: String
}

struct ClipsIndex: Codable {
    var clips: [ClipMetadata]
}

/// 本地存储：
/// ~/Documents/ListeningClipPipe/
/// ├── clips/
/// │   ├── LC_20260626_213522.wav
/// │   └── LC_20260626_213522.json   （每段音频的 metadata.json）
/// └── clips_index.json              （总索引，供 Codex/脚本批量整理）
final class ClipStore {
    let rootDir: URL
    let clipsDir: URL
    var indexURL: URL { rootDir.appendingPathComponent("clips_index.json") }

    private let fm = FileManager.default

    init() throws {
        rootDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/ListeningClipPipe", isDirectory: true)
        clipsDir = rootDir.appendingPathComponent("clips", isDirectory: true)
        try fm.createDirectory(at: clipsDir, withIntermediateDirectories: true)
    }

    /// LC_YYYYMMDD_HHMMSS，同一秒内重复时追加序号保证唯一。
    func makeClipID(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        var id = "LC_" + f.string(from: date)
        var n = 2
        while fm.fileExists(atPath: audioURL(for: id).path) {
            id = "LC_" + f.string(from: date) + "_\(n)"
            n += 1
        }
        return id
    }

    func audioURL(for id: String) -> URL {
        clipsDir.appendingPathComponent("\(id).wav")
    }

    func metadataURL(for id: String) -> URL {
        clipsDir.appendingPathComponent("\(id).json")
    }

    func makeMetadata(id: String, startedAt: Date, duration: Double) -> ClipMetadata {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = .current
        return ClipMetadata(
            id: id,
            created_at: iso.string(from: startedAt),
            duration_sec: (duration * 10).rounded() / 10,
            source: "system_audio",
            audio_file: "\(id).wav",
            local_path: (audioURL(for: id).path as NSString).abbreviatingWithTildeInPath,
            paste_anchor: "🎧 AUDIO_CLIP_ID: \(id)",
            tags: [],
            note: "",
            feishu_doc_url: "",
            feishu_block_id: "",
            feishu_file_token: ""
        )
    }

    /// 结构化文本锚点，粘贴到飞书后供 Codex/脚本定位这段音频。
    func anchorText(for meta: ClipMetadata) -> String {
        """
        🎧 AUDIO_CLIP_ID: \(meta.id)
        duration: \(meta.duration_sec)s
        local_file: \(meta.audio_file)
        source: \(meta.source)
        note:
        """
    }

    /// 保存单条 metadata.json 并更新 clips_index.json。
    func save(_ meta: ClipMetadata) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(meta).write(to: metadataURL(for: meta.id))

        var index = loadIndex()
        index.clips.removeAll { $0.id == meta.id }
        index.clips.append(meta)
        try enc.encode(index).write(to: indexURL)
    }

    func loadIndex() -> ClipsIndex {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(ClipsIndex.self, from: data)
        else {
            return ClipsIndex(clips: [])
        }
        return index
    }

    func lastClip() -> ClipMetadata? {
        loadIndex().clips.last
    }
}
