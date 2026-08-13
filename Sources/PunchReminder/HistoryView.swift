import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近 90 天。到点后才能改打卡状态，超过宽限记为缺卡，仍可补记。")
                .font(.callout)
                .foregroundStyle(Surface.secondary)

            if grouped.isEmpty {
                Text("暂无记录。")
                    .foregroundStyle(Surface.secondary)
                    .padding(.top, 24)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(grouped, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.day)
                                    .font(.headline)
                                    .foregroundStyle(Surface.secondary)
                                ForEach(group.entries) { entry in
                                    historyRow(entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        let punched = entry.confirmedAt != nil
        let canModify = store.canModify(entry: entry)
        return SettingsCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(entry.ruleName)
                            .font(.headline)
                            .foregroundStyle(Surface.label)
                        Text(entry.deadlineText)
                            .foregroundStyle(Surface.secondary)
                            .monospacedDigit()
                    }
                    if punched {
                        Text("已打卡 \(timeText(entry.confirmedAt!))")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else if entry.missed {
                        Text("缺卡")
                            .font(.callout)
                            .foregroundStyle(.red)
                    } else {
                        Text("进行中")
                            .font(.callout)
                            .foregroundStyle(Surface.secondary)
                    }
                }
                Spacer()
                if canModify {
                    if punched {
                        Button("改为未打卡") {
                            store.setPunched(entry: entry, punched: false)
                        }
                    } else {
                        Button("标记已打卡") {
                            store.beginConfirm(entry: entry)
                            NSApp.activate()
                            openWindow(id: "confirm-punch")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var grouped: [(day: String, entries: [HistoryEntry])] {
        let keys = Set(store.history.map(\.day)).sorted(by: >)
        return keys.map { day in
            (
                day,
                store.history.filter { $0.day == day }.sorted {
                    $0.deadlineHour * 60 + $0.deadlineMinute < $1.deadlineHour * 60 + $1.deadlineMinute
                }
            )
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
