import SwiftUI
import ServiceManagement

@MainActor
final class UsageStore: ObservableObject {
    @Published var claude = ProviderUsage(id: "claude", name: "Claude Code")
    @Published var codex = ProviderUsage(id: "codex", name: "ChatGPT Codex")
    @Published var updatedAt: Date?

    private var lastClaudeFetch: Date = .distantPast
    private var timer: Timer?

    /// Dữ liệu local làm mới mỗi 30s; API Claude tối đa 1 lần / 3 phút để tránh bị rate-limit.
    private let tick: TimeInterval = 30
    private let claudeApiInterval: TimeInterval = 180

    init() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
        Snapshot.runIfRequested(store: self)
    }

    func refresh(force: Bool) {
        codex = CodexProvider.fetch()
        claude.status = ClaudeProvider.status()
        updatedAt = Date()

        guard force || Date().timeIntervalSince(lastClaudeFetch) >= claudeApiInterval else { return }
        lastClaudeFetch = Date()
        Task {
            let r = await ClaudeProvider.fetchUsage()
            claude.session = r.session
            claude.weekly = r.weekly
            claude.error = r.error
        }
    }

    var menuTitle: String {
        func pct(_ u: ProviderUsage) -> String { u.session.map { "\(Int($0.percent.rounded()))%" } ?? "–" }
        return "C \(pct(claude)) · X \(pct(codex))"
    }
}

/// App chỉ sống trên menu bar nên mở lại từ Finder/Spotlight sẽ không có gì hiện ra -> tự mở popover.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let button = NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .lazy.compactMap { $0.contentView.flatMap(Self.findButton) }.first
        button?.performClick(nil)
        return false
    }

    private static func findButton(in view: NSView) -> NSStatusBarButton? {
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews { if let b = findButton(in: sub) { return b } }
        return nil
    }
}

@main
struct AIUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            Text(store.menuTitle).monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderCard(usage: store.claude)
            Divider()
            ProviderCard(usage: store.codex)
            Divider()
            LaunchAtLoginToggle()
            HStack {
                if let t = store.updatedAt {
                    Text("Cập nhật \(t.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Làm mới") { store.refresh(force: true) }
                Button("Thoát") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Khởi động cùng macOS", isOn: Binding(
                get: { enabled },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch {
                        self.error = "Không đổi được: \(error.localizedDescription)"
                    }
                    enabled = SMAppService.mainApp.status == .enabled
                }))
                .toggleStyle(.switch).controlSize(.mini).font(.caption)
            if let error { Text(error).font(.caption2).foregroundStyle(.orange) }
        }
    }
}

struct ProviderCard: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(usage.name).font(.headline)
                Spacer()
                Circle()
                    .fill(usage.status == .running ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(usage.status == .running ? "Đang chạy" : "Nghỉ")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let err = usage.error {
                Text(err).font(.caption).foregroundStyle(.orange)
            }
            UsageRow(label: "Session (5 giờ)", window: usage.session)
            UsageRow(label: "Weekly (7 ngày)", window: usage.weekly)
        }
    }
}

struct UsageRow: View {
    let label: String
    let window: UsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(window.map { "\(Int($0.percent.rounded()))%" } ?? "–")
                    .font(.caption.monospacedDigit().bold())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(max((window?.percent ?? 0) / 100, 0), 1))
                }
            }
            .frame(height: 6)
            if let r = window?.resetsAt {
                Text("Reset sau \(remaining(until: r))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        let p = window?.percent ?? 0
        return p >= 90 ? .red : p >= 70 ? .orange : .accentColor
    }

    private func remaining(until date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSinceNow))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d) ngày \(h) giờ" }
        if h > 0 { return "\(h) giờ \(m) phút" }
        return "\(m) phút"
    }
}
