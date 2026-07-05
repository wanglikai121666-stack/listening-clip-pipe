import AppKit
import SwiftUI

extension Notification.Name {
    /// 录音列表变化（新会话保存/删除）时发出，Library 窗口据此刷新。
    static let lcpClipsChanged = Notification.Name("LCPClipsChanged")
}

extension ClipMetadata: Identifiable {}

// MARK: - 数据模型

@MainActor
final class LibraryModel: ObservableObject {
    @Published var sessions: [ClipMetadata] = []
    @Published var busyIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: ASRService.apiKeyDefaultsKey) }
    }
    @Published var preroll: Double {
        didSet { UserDefaults.standard.set(preroll, forKey: "MarkPrerollSeconds") }
    }

    static let prerollChoices: [Double] = [0, 0.1, 0.2, 0.3, 0.5, 1.0]

    let store: ClipStore
    private let asr = ASRService()

    init(store: ClipStore) {
        self.store = store
        apiKey = UserDefaults.standard.string(forKey: ASRService.apiKeyDefaultsKey) ?? ""
        preroll = UserDefaults.standard.object(forKey: "MarkPrerollSeconds") as? Double ?? 0.3
        reload()
        NotificationCenter.default.addObserver(
            forName: .lcpClipsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        sessions = store.loadIndex().clips.reversed()
    }

    func hasReport(_ meta: ClipMetadata) -> Bool {
        store.hasReport(for: meta.id)
    }

    func transcribe(_ meta: ClipMetadata) {
        guard !busyIDs.contains(meta.id) else { return }
        busyIDs.insert(meta.id)
        Task {
            do {
                _ = try await ReportGenerator.generate(meta: meta, store: store, asr: asr)
            } catch {
                errorMessage = error.localizedDescription
            }
            busyIDs.remove(meta.id)
            reload()
        }
    }

    func openReport(_ meta: ClipMetadata) {
        NSWorkspace.shared.open(store.reportURL(for: meta.id))
    }

    func play(_ meta: ClipMetadata) {
        NSWorkspace.shared.open(store.fileURL(for: meta))
    }

    func revealInFinder(_ meta: ClipMetadata) {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: meta)])
    }

    func delete(_ meta: ClipMetadata) {
        do {
            try store.remove(meta)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }
}

// MARK: - 视图

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @State private var deleteTarget: ClipMetadata?

    var body: some View {
        VStack(spacing: 0) {
            settingsBar
            Divider()
            if model.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(minWidth: 820, minHeight: 480)
        .alert(
            "出错了",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "删除 \(deleteTarget?.id ?? "")？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("删除录音、切分段和报告", role: .destructive) {
                if let meta = deleteTarget { model.delete(meta) }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        }
    }

    private var settingsBar: some View {
        HStack(spacing: 16) {
            Picker("打标提前量", selection: $model.preroll) {
                ForEach(LibraryModel.prerollChoices, id: \.self) { value in
                    Text(value == 0 ? "关闭" : String(format: "%.1fs", value)).tag(value)
                }
            }
            .fixedSize()
            .help("按空格开标时，绿段起点自动回拨的秒数（全局设置）")

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                Text("SiliconFlow API Key")
                SecureField("sk-…", text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Image(systemName: model.apiKey.isEmpty ? "xmark.circle" : "checkmark.circle.fill")
                    .foregroundStyle(model.apiKey.isEmpty ? .red : .green)
                    .help(model.apiKey.isEmpty ? "未设置，转录不可用" : "已设置（仅存本机）")
            }

            Spacer()

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新列表")
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有录音。按 ⌥Z 开始第一场听力训练。")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionList: some View {
        List(model.sessions) { meta in
            SessionRow(
                meta: meta,
                busy: model.busyIDs.contains(meta.id),
                hasReport: model.hasReport(meta),
                onPlay: { model.play(meta) },
                onTranscribe: { model.transcribe(meta) },
                onOpenReport: { model.openReport(meta) },
                onReveal: { model.revealInFinder(meta) },
                onDelete: { deleteTarget = meta }
            )
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
    }
}

private struct SessionRow: View {
    let meta: ClipMetadata
    let busy: Bool
    let hasReport: Bool
    let onPlay: () -> Void
    let onTranscribe: () -> Void
    let onOpenReport: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    private var durationText: String {
        let secs = Int(meta.duration_sec)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meta.id).font(.system(.body, design: .monospaced)).bold()
                HStack(spacing: 8) {
                    Text(durationText)
                    Text("\(meta.segments?.count ?? 0) 个打标")
                        .foregroundStyle((meta.segments?.isEmpty ?? true) ? .secondary : Color.green)
                    if hasReport {
                        Label("已转录", systemImage: "doc.text")
                            .foregroundStyle(.blue)
                    }
                    Text(meta.feishu_doc_url.isEmpty ? "未上传飞书" : "已上传飞书")
                        .foregroundStyle(meta.feishu_doc_url.isEmpty ? .secondary : Color.green)
                }
                .font(.caption)
            }

            Spacer()

            if busy {
                ProgressView().controlSize(.small)
                Text("转录中…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("播放", action: onPlay)
                Button(hasReport ? "重新转录" : "转录", action: onTranscribe)
                Button("查看转录", action: onOpenReport)
                    .disabled(!hasReport)
                Button {
                    onReveal()
                } label: {
                    Image(systemName: "folder")
                }
                .help("在 Finder 中显示")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("删除")
            }
        }
    }
}
