import Foundation

/// SiliconFlow 语音转文本（POST /v1/audio/transcriptions，SenseVoiceSmall）。
///
/// API Key 存在本机 UserDefaults（Library 窗口里设置），不写入代码仓库。
/// WAV 体积大（约 10MB/分钟），上传前先用系统自带 afconvert 压成 AAC/M4A，
/// 一小时录音约 25MB，低于接口 50MB 限制。
final class ASRService {
    static let apiKeyDefaultsKey = "SiliconFlowAPIKey"
    static let endpoint = URL(string: "https://api.siliconflow.cn/v1/audio/transcriptions")!
    static let model = "FunAudioLLM/SenseVoiceSmall"

    enum ASRError: LocalizedError {
        case noAPIKey
        case transcodeFailed(String)
        case badResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "未设置 SiliconFlow API Key。请打开 Library 窗口，在设置栏粘贴 Key。"
            case .transcodeFailed(let detail):
                return "音频压缩失败（afconvert）：\(detail)"
            case .badResponse:
                return "ASR 服务返回了无法解析的响应。"
            case .http(let code, let body):
                return "ASR 请求失败（HTTP \(code)）：\(body.prefix(300))"
            }
        }
    }

    var hasAPIKey: Bool {
        !(UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey) ?? "").isEmpty
    }

    func transcribe(fileURL: URL) async throws -> String {
        guard let key = UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey),
              !key.isEmpty else { throw ASRError.noAPIKey }
        return try await transcribe(fileURL: fileURL, apiKey: key)
    }

    func transcribe(fileURL: URL, apiKey: String) async throws -> String {
        let uploadURL = try transcodeToM4A(fileURL)
        defer { try? FileManager.default.removeItem(at: uploadURL) }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        let boundary = "----LCPBoundary\(UUID().uuidString)"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(uploadURL.lastPathComponent)\"\r\n"
        )
        body.appendUTF8("Content-Type: audio/mp4\r\n\r\n")
        body.append(try Data(contentsOf: uploadURL))
        body.appendUTF8("\r\n--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendUTF8("\(Self.model)\r\n")
        body.appendUTF8("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ASRError.badResponse }
        guard http.statusCode == 200 else {
            throw ASRError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        struct TranscriptionResponse: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw ASRError.badResponse
        }
        return Self.cleanup(decoded.text)
    }

    /// SenseVoice 系列偶尔会带 <|en|><|NEUTRAL|> 之类的控制标记，剥掉。
    static func cleanup(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<\|[^|>]*\|>"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcodeToM4A(_ url: URL) throws -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("lcp-\(UUID().uuidString).m4a")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "m4af", "-d", "aac", "-b", "64000", url.path, out.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw ASRError.transcodeFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw ASRError.transcodeFailed("exit \(process.terminationStatus) \(err.prefix(200))")
        }
        return out
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
