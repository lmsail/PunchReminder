import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.todayOccurrences.isEmpty {
                emptyState
            } else {
                occurrenceList
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .background(Surface.window)
        .onAppear {
            store.requestNotificationPermission()
            store.refreshAuthorizationStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("朝夕打卡")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Surface.label)
                Text(headerDate)
                    .font(.subheadline)
                    .foregroundStyle(Surface.secondary)
            }
            Spacer()
            if let clockOut = ReminderLogic.clockOutOccurrence(from: store.todayOccurrences) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.now >= clockOut.deadline ? "已下班" : "下班倒计时")
                        .font(.subheadline)
                        .foregroundStyle(Surface.secondary)
                    Text(
                        store.now >= clockOut.deadline
                            ? clockOut.rule.timeText
                            : ReminderLogic.countdownText(to: clockOut.deadline, now: store.now)
                    )
                    .font(.system(size: store.fontSize.menuBarPointSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Surface.label)
                }
            }
            if store.dayRuntime.paused {
                StatusChip(text: "已暂停", tone: .warning)
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.title2)
                .foregroundStyle(Surface.secondary)
            Text("今天没有打卡安排")
                .font(.callout)
                .foregroundStyle(Surface.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var occurrenceList: some View {
        VStack(spacing: 12) {
            ForEach(store.todayOccurrences, id: \.rule.id) { occurrence in
                occurrenceRow(occurrence)
            }
        }
        .padding(16)
    }

    private func occurrenceRow(_ occurrence: ReminderLogic.Occurrence) -> some View {
        let status = store.status(for: occurrence)
        let canModify = store.canModify(occurrence)
        return SettingsCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(occurrence.rule.name)
                            .font(.headline)
                            .foregroundStyle(Surface.label)
                        Text(occurrence.rule.timeText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Surface.secondary)
                    }
                    Text(statusCaption(status, occurrence: occurrence, canModify: canModify))
                        .font(.subheadline)
                        .foregroundStyle(Surface.secondary)
                }
                Spacer()
                statusChip(status)
                if canModify {
                    if status == .confirmed {
                        Button("改为未打卡") {
                            store.unconfirm(ruleId: occurrence.rule.id)
                        }
                        .controlSize(.regular)
                    } else {
                        Button("标记已打卡") {
                            store.beginConfirm(occurrence: occurrence)
                            NSApp.activate()
                            openWindow(id: "confirm-punch")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                Button(store.dayRuntime.paused ? "恢复今日提醒" : "今日暂停全部") {
                    store.togglePaused()
                }
                Button("设置…") {
                    NSApp.activate()
                    openWindow(id: "settings")
                }
                Button("历史记录") {
                    NSApp.activate()
                    openWindow(id: "history")
                }
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Surface.label)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusChip(_ status: ReminderLogic.PunchStatus) -> some View {
        switch status {
        case .confirmed:
            StatusChip(text: "已打卡", tone: .success)
        case .expired:
            StatusChip(text: "缺卡", tone: .danger)
        case .reminding:
            StatusChip(text: "提醒中", tone: .warning)
        case .grace:
            StatusChip(text: "宽限中", tone: .warning)
        case .paused:
            StatusChip(text: "已暂停", tone: .warning)
        default:
            StatusChip(text: statusText(status), tone: .neutral)
        }
    }

    private var headerDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: store.now)
    }

    private func statusText(_ status: ReminderLogic.PunchStatus) -> String {
        switch status {
        case .upcoming: return "待开始"
        case .reminding: return "提醒中"
        case .grace: return "宽限中"
        case .snoozed: return "稍后"
        case .confirmed: return "已打卡"
        case .expired: return "缺卡"
        case .paused: return "已暂停"
        case .skipped: return "已跳过"
        }
    }

    private func statusCaption(
        _ status: ReminderLogic.PunchStatus,
        occurrence: ReminderLogic.Occurrence,
        canModify: Bool
    ) -> String {
        if status == .confirmed {
            if let punchedAt = store.confirmedAt(for: occurrence) {
                return "打卡时间 \(timeText(punchedAt))"
            }
            return "已打卡"
        }
        if store.now >= occurrence.deadline {
            return ReminderLogic.lateText(
                deadline: occurrence.deadline,
                now: store.now,
                clockOut: ReminderLogic.isClockOutName(occurrence.rule.name)
            )
        }
        let window = "\(timeText(occurrence.windowStart))–\(timeText(occurrence.graceEnd))"
        if !canModify {
            return "\(window)  ·  到点后可改状态"
        }
        return window
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
