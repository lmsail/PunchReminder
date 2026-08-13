import SwiftUI

struct OverridesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDay = Date()
    @State private var kind: OverrideKind = .skipDay
    @State private var selectedRuleId: UUID?
    @State private var replaceTime = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDayTitle)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Surface.label)
                    Text("请假或加班改点，只影响这一天。")
                        .font(.title3)
                        .foregroundStyle(Surface.secondary)
                }

                MonthCalendar(date: $selectedDay)

                VStack(alignment: .leading, spacing: 12) {
                    Text("调整类型")
                        .font(.headline)
                        .foregroundStyle(Surface.label)
                    Picker("类型", selection: $kind) {
                        Text("全天不上班").tag(OverrideKind.skipDay)
                        Text("跳过某条规则").tag(OverrideKind.skipRule)
                        Text("修改某条规则时间").tag(OverrideKind.replaceTime)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .labelsHidden()
                }

                if kind != .skipDay {
                    Picker("规则", selection: $selectedRuleId) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(store.rules) { rule in
                            Text("\(rule.name) \(rule.timeText)").tag(Optional(rule.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.large)
                }

                if kind == .replaceTime {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("改为")
                            .font(.headline)
                            .foregroundStyle(Surface.label)
                        ClockTimePicker(date: $replaceTime)
                    }
                }

                HStack {
                    Spacer()
                    Button("添加调整") {
                        addOverride()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canAdd)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("已保存的调整")
                        .font(.headline)
                        .foregroundStyle(Surface.label)
                    if upcomingOverrides.isEmpty {
                        Text("暂无单日调整。")
                            .foregroundStyle(Surface.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(upcomingOverrides) { item in
                                SettingsCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.day)
                                                .font(.headline)
                                                .foregroundStyle(Surface.label)
                                            Text(overrideCaption(item))
                                                .font(.callout)
                                                .foregroundStyle(Surface.secondary)
                                        }
                                        Spacer()
                                        Button("删除", role: .destructive) {
                                            store.deleteOverride(id: item.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedRuleId == nil {
                selectedRuleId = store.rules.first?.id
            }
        }
    }

    private var selectedDayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: selectedDay)
    }

    private var canAdd: Bool {
        switch kind {
        case .skipDay:
            return true
        case .skipRule, .replaceTime:
            return selectedRuleId != nil
        }
    }

    private var upcomingOverrides: [DayOverride] {
        store.overrides.sorted { $0.day > $1.day }
    }

    private func addOverride() {
        let day = ReminderLogic.dayString(from: selectedDay)
        var hour: Int?
        var minute: Int?
        if kind == .replaceTime {
            hour = Calendar.current.component(.hour, from: replaceTime)
            minute = Calendar.current.component(.minute, from: replaceTime)
        }
        store.addOverride(
            DayOverride(
                id: UUID(),
                day: day,
                kind: kind,
                ruleId: kind == .skipDay ? nil : selectedRuleId,
                hour: hour,
                minute: minute
            )
        )
    }

    private func overrideCaption(_ item: DayOverride) -> String {
        switch item.kind {
        case .skipDay:
            return "全天不上班，当天不提醒"
        case .skipRule:
            let name = store.rules.first { $0.id == item.ruleId }?.name ?? "规则"
            return "跳过「\(name)」"
        case .replaceTime:
            let name = store.rules.first { $0.id == item.ruleId }?.name ?? "规则"
            return "「\(name)」改为 \(item.timeText ?? "--:--")"
        }
    }
}
