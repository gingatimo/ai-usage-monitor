import Foundation

/// Lấy usage Claude qua OAuth usage API, dùng token Claude Code lưu trong Keychain.
enum ClaudeProvider {
    static let projects = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    /// Chỉ trạng thái chạy/nghỉ, đọc từ log local (rẻ, gọi thường xuyên được).
    static func status() -> RunStatus {
        // mtime thư mục không đổi khi file bên trong được ghi thêm -> phải xét mtime từng file.
        let dirs = ((try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath }
        let latest = dirs.compactMap { FileScan.jsonlFiles(in: $0).first?.1 }.max()
        return FileScan.status(lastWrite: latest)
    }

    static func fetchUsage() async -> (session: UsageWindow?, weekly: UsageWindow?, error: String?) {
        let token: String
        switch readToken() {
        case .success(let t): token = t
        case .failure(let e): return (nil, nil, e.message)
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return (nil, nil, "Token hết hạn – mở Claude Code để đăng nhập lại") }
            guard code == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return (nil, nil, "API lỗi (HTTP \(code))") }
            return (window(obj["five_hour"]), window(obj["seven_day"]), nil)
        } catch {
            return (nil, nil, "Không kết nối được API")
        }
    }

    struct TokenError: Error { let message: String }

    private static func readToken() -> Result<String, TokenError> {
        // Dùng /usr/bin/security để quyền "Always Allow" không mất khi rebuild app.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return .failure(TokenError(message: "Không chạy được security")) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { return .failure(TokenError(message: "Chưa đăng nhập Claude Code (không đọc được Keychain)")) }
        if let exp = oauth["expiresAt"] as? Double, exp / 1000 < Date().timeIntervalSince1970 {
            return .failure(TokenError(message: "Token hết hạn – mở Claude Code để đăng nhập lại"))
        }
        return .success(token)
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func window(_ raw: Any?) -> UsageWindow? {
        guard let w = raw as? [String: Any], let pct = w["utilization"] as? Double else { return nil }
        let reset = (w["resets_at"] as? String).flatMap { isoFrac.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        return UsageWindow(percent: pct, resetsAt: reset)
    }
}
