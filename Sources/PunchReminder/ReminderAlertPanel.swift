import AppKit
import SwiftUI

extension Notification.Name {
    static let punchReminderOpenConfirm = Notification.Name("punchReminderOpenConfirm")
}

@MainActor
final class ReminderAlertPanelController: NSObject, NSWindowDelegate {
    static let shared = ReminderAlertPanelController()

    var onClosed: (() -> Void)?

    private var panel: NSPanel?

    func show(store: AppStore) {
        let panel = makePanel()
        panel.delegate = self
        let hosting = NSHostingView(rootView: ReminderAlertView().environmentObject(store))
        hosting.wantsLayer = true
        let size = NSSize(width: 360, height: 78)
        hosting.frame.size = size
        panel.contentView = hosting
        panel.setContentSize(size)
        position(panel, size: size)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }

    private func makePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 78),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        panel.setFrame(
            NSRect(
                x: screen.midX - size.width / 2,
                y: screen.maxY - size.height - 16,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }
}

struct ReminderAlertView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if let alert = store.enhancedAlert {
                HStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 36, height: 36)))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .lineLimit(1)
                            Text(alert.body)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider()

                    VStack(spacing: 0) {
                        notificationAction("稍后") {
                            store.snoozeEnhancedAlert()
                        }
                        Divider()
                        notificationAction(alert.ruleId == nil ? "知道了" : "打卡") {
                            if alert.ruleId == nil {
                                store.dismissEnhancedAlert()
                            } else {
                                store.confirmEnhancedAlert()
                            }
                        }
                    }
                    .frame(width: 72)
                }
            }
        }
        .frame(width: 360, height: 78)
        .background(NotificationMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private func notificationAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NotificationMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
