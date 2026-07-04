import AppKit

/// 剪贴板写入，对应 PRD 第 10 节的三种模式。
final class ClipboardService {
    private var pb: NSPasteboard { NSPasteboard.general }

    /// 测试 A（composite）：同一个 pasteboard item 同时带 file URL 和纯文本锚点。
    /// 目标 App（飞书）按自己支持的类型取用——若飞书优先取文件，则粘出音频附件；
    /// 若测试 A 失败，用下面两个单独模式做双复制兜底。
    func copyComposite(fileURL: URL, anchor: String) {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString(anchor, forType: .string)
        pb.writeObjects([item])
    }

    /// 只复制音频文件（file URL 对象，等价于在 Finder 里 Cmd+C 该文件）。
    func copyAudioFile(_ fileURL: URL) {
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
    }

    /// 只复制文本锚点。
    func copyAnchor(_ anchor: String) {
        pb.clearContents()
        pb.setString(anchor, forType: .string)
    }
}
