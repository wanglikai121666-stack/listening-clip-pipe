import AVFoundation
import AppKit
import SwiftUI

/// 详情页里的可编辑绿标（编辑期间只是时间区间，点「保存」才重新切分文件）。
struct EditableMark: Identifiable, Equatable {
    let id = UUID()
    var start: Double
    var end: Double
}

// MARK: - 模型：播放器 + 绿标编辑

@MainActor
final class SessionDetailModel: ObservableObject {
    @Published var meta: ClipMetadata
    @Published var marks: [EditableMark]
    @Published var selectedID: UUID?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var dirty = false
    @Published var errorMessage: String?

    let store: ClipStore
    let duration: Double
    private var player: AVAudioPlayer?
    private var timer: Timer?

    static let defaultMarkLength = 0.5
    static let minMarkLength = 0.1

    init(meta: ClipMetadata, store: ClipStore) {
        self.meta = meta
        self.store = store
        self.marks = (meta.segments ?? []).map {
            EditableMark(start: $0.start_sec, end: $0.end_sec)
        }
        let player = try? AVAudioPlayer(contentsOf: store.fileURL(for: meta))
        self.player = player
        self.duration = player?.duration ?? meta.duration_sec
        player?.prepareToPlay()

        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        // 播放到结尾后 AVAudioPlayer 自动停止
        if isPlaying && !player.isPlaying {
            isPlaying = false
        }
    }

    // MARK: 播放

    func togglePlay() {
        guard let player else {
            errorMessage = "无法打开音频文件：\(meta.audio_file)"
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to time: Double) {
        let clamped = min(max(0, time), duration)
        player?.currentTime = clamped
        currentTime = clamped
    }

    func stopPlayback() {
        player?.stop()
        timer?.invalidate()
        timer = nil
    }

    // MARK: 绿标编辑

    var selectedMark: EditableMark? {
        marks.first { $0.id == selectedID }
    }

    /// 在播放头当前位置新建绿标（默认 0.5s）。
    func addMarkAtPlayhead() {
        let start = min(currentTime, max(0, duration - Self.defaultMarkLength))
        let end = min(start + Self.defaultMarkLength, duration)
        let mark = EditableMark(start: start, end: end)
        marks.append(mark)
        selectedID = mark.id
        dirty = true
    }

    func deleteSelected() {
        guard let selectedID else { return }
        marks.removeAll { $0.id == selectedID }
        self.selectedID = nil
        dirty = true
    }

    func setStart(of id: UUID, to time: Double) {
        guard let i = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[i].start = min(max(0, time), marks[i].end - Self.minMarkLength)
        dirty = true
    }

    func setEnd(of id: UUID, to time: Double) {
        guard let i = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[i].end = max(min(duration, time), marks[i].start + Self.minMarkLength)
        dirty = true
    }

    /// 保存：按当前绿标重新切分文件，更新元数据/索引。
    func save() {
        do {
            let ranges = marks.map { (start: $0.start, end: $0.end) }
            meta = try store.reslice(meta: meta, ranges: ranges)
            dirty = false
            NotificationCenter.default.post(name: .lcpClipsChanged, object: nil)
        } catch {
            errorMessage = "重新切分失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 详情页视图

struct SessionDetailView: View {
    @StateObject private var model: SessionDetailModel
    @Environment(\.dismiss) private var dismiss

    init(meta: ClipMetadata, store: ClipStore) {
        _model = StateObject(wrappedValue: SessionDetailModel(meta: meta, store: store))
    }

    private func timeText(_ t: Double) -> String {
        String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 返回主界面
            HStack {
                Button {
                    model.stopPlayback()
                    dismiss()
                } label: {
                    Label("返回列表", systemImage: "chevron.left")
                }
                .keyboardShortcut(.escape, modifiers: [])
                if model.dirty {
                    Text("（有未保存的绿标修改）")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }

            // 播放控制
            HStack(spacing: 12) {
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                Text("\(timeText(model.currentTime)) / \(timeText(model.duration))")
                    .font(.system(.title3, design: .monospaced))

                Spacer()

                Text("\(model.marks.count) 个绿标")
                    .foregroundStyle(.green)
            }

            // 可拖动进度条 + 绿标编辑
            MarkTimelineView(model: model)

            // 编辑操作
            HStack(spacing: 12) {
                Button("＋ 在当前位置新建绿标（0.5s）") {
                    model.addMarkAtPlayhead()
                }
                Button("删除选中绿标", role: .destructive) {
                    model.deleteSelected()
                }
                .disabled(model.selectedMark == nil)

                Spacer()

                if model.dirty {
                    Text("未保存").foregroundStyle(.orange).font(.caption)
                }
                Button("保存并重新切分") {
                    model.save()
                }
                .keyboardShortcut("s")
                .disabled(!model.dirty)
            }

            Text("拖动进度条跳转播放；点击绿标选中后，拖动两端圆形手柄调整起止位置。保存后会按新区间重新生成切分文件（旧报告需重新转录）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selected = model.selectedMark {
                Text("选中绿标：\(timeText(selected.start)) – \(timeText(selected.end))（\(String(format: "%.1f", selected.end - selected.start))s）")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding(20)
        .navigationTitle(model.meta.id)
        .onDisappear { model.stopPlayback() }
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
    }
}

// MARK: - 时间轴：进度 + 绿标 + 拖动手柄

struct MarkTimelineView: View {
    @ObservedObject var model: SessionDetailModel

    private let barHeight: CGFloat = 28
    private let handleSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(model.duration, 0.01)

            let xPos: (Double) -> CGFloat = { CGFloat($0 / total) * width }
            let time: (CGFloat) -> Double = { Double(min(max($0, 0), width) / width) * total }

            ZStack(alignment: .topLeading) {
                // 底轨（拖动 = 跳转播放位置）
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: width, height: barHeight)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                            .onChanged { model.seek(to: time($0.location.x)) }
                    )

                // 已播放进度
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: max(0, xPos(model.currentTime)), height: barHeight)
                    .allowsHitTesting(false)

                // 绿标
                ForEach(model.marks) { mark in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(model.selectedID == mark.id
                            ? Color.green
                            : Color.green.opacity(0.5))
                        .frame(width: max(4, xPos(mark.end) - xPos(mark.start)), height: barHeight)
                        .offset(x: xPos(mark.start))
                        .onTapGesture { model.selectedID = mark.id }
                }

                // 选中绿标的两端手柄
                if let selected = model.selectedMark {
                    handle(at: xPos(selected.start)) { x in
                        model.setStart(of: selected.id, to: time(x))
                    }
                    handle(at: xPos(selected.end)) { x in
                        model.setEnd(of: selected.id, to: time(x))
                    }
                }

                // 播放头
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red)
                    .frame(width: 2, height: barHeight + 10)
                    .offset(x: xPos(model.currentTime) - 1, y: -5)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(name: "timeline")
        }
        .frame(height: barHeight + 14)
        .padding(.vertical, 6)
    }

    private func handle(at x: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.green, lineWidth: 2.5))
            .frame(width: handleSize, height: handleSize)
            .offset(x: x - handleSize / 2, y: (barHeight - handleSize) / 2)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
                    .onChanged { onDrag($0.location.x) }
            )
    }
}
