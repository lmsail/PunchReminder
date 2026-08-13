import SwiftUI
import AppKit

@main
struct PunchReminderApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .appChrome(store)
                .onAppear { store.appearance.apply() }
        } label: {
            MenuBarStatusLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Window("朝夕打卡设置", id: "settings") {
            SettingsView()
                .environmentObject(store)
                .appChrome(store)
                .background(Surface.window)
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)

        Window("朝夕打卡历史", id: "history") {
            HistoryView()
                .environmentObject(store)
                .appChrome(store)
                .padding(20)
                .background(Surface.window)
                .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 600, height: 480)

        Window("选择打卡时间", id: "confirm-punch") {
            ConfirmPunchView()
                .environmentObject(store)
                .appChrome(store)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 320)
    }
}

struct MenuBarStatusLabel: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(opacity: store.menuBarIconOn ? 1 : 0.3))
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text(store.menuBarTitle)
                .font(.system(size: store.fontSize.menuBarPointSize, weight: .medium).monospacedDigit())
        }
        .id("\(store.menuBarIconOn)-\(store.menuBarTitle)")
        .onReceive(NotificationCenter.default.publisher(for: .punchReminderOpenConfirm)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "confirm-punch")
        }
    }
}

enum MenuBarIcon {
    static func image(opacity: CGFloat) -> NSImage {
        let source = baseImage
        if opacity >= 1 {
            return source
        }
        let size = source.size
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity)
            return true
        }
    }

    private static var baseImage: NSImage {
        if let cached {
            return cached
        }
        let source = NSApp.applicationIconImage
        let image = (source?.copy() as? NSImage) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        cached = image
        return image
    }

    private static var cached: NSImage?
}
