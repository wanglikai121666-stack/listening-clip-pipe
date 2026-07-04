import Foundation

/// P1 接口占位（PRD 15.6）：P0 不实现飞书自动同步，只保留接口定义。
///
/// P1 计划：
/// - 上传当天 clip index。
/// - 创建/更新飞书日记文档。
/// - 把每条音频记录写入指定文档。
protocol FeishuSyncService {
    func uploadDailyIndex(_ index: ClipsIndex) async throws
    func appendClip(_ meta: ClipMetadata, toDocument documentURL: URL) async throws
}
