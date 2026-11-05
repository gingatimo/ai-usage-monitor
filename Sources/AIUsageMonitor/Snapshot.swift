import SwiftUI

/// Chế độ kiểm tra: AIUM_SNAPSHOT=/path/out.png -> render popover ra PNG, in tiêu đề menu bar rồi thoát.
@MainActor
enum Snapshot {
    static func runIfRequested(store: UsageStore) {
        guard let path = ProcessInfo.processInfo.environment["AIUM_SNAPSHOT"] else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // chờ API Claude trả về
            let renderer = ImageRenderer(content: ContentView(store: store).background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            print("menu title:", store.menuTitle)
            exit(0)
        }
    }
}
