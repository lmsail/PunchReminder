import SwiftUI
import AppKit

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case rules
    case preview
    case overrides
    case history
    case general

    var id: SettingsSection { self }

    var title: String {
        switch self {
        case .rules: return "打卡规则"
        case .preview: return "今日预览"
        case .overrides: return "单日调整"
        case .history: return "历史记录"
        case .general: return "通用"
        }
    }

    var symbol: String {
        switch self {
        case .rules: return "list.bullet.rectangle"
        case .preview: return "calendar"
        case .overrides: return "calendar.badge.exclamationmark"
        case .history: return "clock.arrow.circlepath"
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @SceneStorage("settings-section") private var sectionRaw = SettingsSection.rules.rawValue

    private var section: SettingsSection {
        SettingsSection(rawValue: sectionRaw) ?? .rules
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("朝夕打卡")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Surface.label)
                    Text("打卡助手")
                        .font(.caption)
                        .foregroundStyle(Surface.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)
                List(SettingsSection.allCases, selection: sectionBinding) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .background(Surface.window)
            .navigationSplitViewColumnWidth(min: 168, ideal: 188, max: 220)
        } detail: {
            Group {
                switch section {
                case .rules:
                    RulesSettingsView()
                case .preview:
                    TodayPreviewView()
                case .overrides:
                    OverridesView()
                case .history:
                    HistoryView()
                case .general:
                    GeneralSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .background(Surface.window)
            .navigationTitle(section.title)
        }
        .frame(minWidth: 760, minHeight: 500)
        .appChrome(store)
    }

    private var sectionBinding: Binding<SettingsSection> {
        Binding(
            get: { SettingsSection(rawValue: sectionRaw) ?? .rules },
            set: { sectionRaw = $0.rawValue }
        )
    }
}

struct RulesSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: PunchRule?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("每条规则独立配置时间、星期、提前窗口、间隔和到点后宽限。可拖动排序，未手动调整时按时间正序。一天可配置多次打卡。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("新增规则") {
                    editing = PunchRule(
                        id: UUID(),
                        name: "下班",
                        hour: 18,
                        minute: 0,
                        weekdays: [2, 3, 4, 5, 6],
                        leadMinutes: 20,
                        intervalMinutes: 2,
                        graceMinutes: 10,
                        enabled: true
                    )
                    isAdding = true
                }
            }

            if !store.conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("同一时刻存在多条规则")
                        .font(.subheadline.weight(.semibold))
                    ForEach(store.conflicts, id: \.self) { message in
                        Text(message)
                            .font(.callout)
                    }
                }
                .foregroundStyle(.orange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            List {
                ForEach(store.rules) { rule in
                    ruleRow(rule)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: store.moveRules)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
        }
        .sheet(item: $editing) { rule in
            RuleEditorView(
                rule: rule,
                isNew: isAdding,
                onCancel: {
                    editing = nil
                    isAdding = false
                },
                onSave: { saved in
                    if isAdding {
                        store.addRule(saved)
                    } else {
                        store.updateRule(saved)
                    }
                    editing = nil
                    isAdding = false
                }
            )
        }
    }

    private func ruleRow(_ rule: PunchRule) -> some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .help("拖动排序")
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(rule.name)
                            .font(.headline)
                        Text(rule.timeText)
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !rule.enabled {
                            Text("已关闭")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("周\(WeekdayFormat.joined(rule.weekdays))  ·  提前 \(rule.leadMinutes) 分钟  ·  每 \(rule.intervalMinutes) 分钟  ·  宽限 \(rule.graceMinutes) 分钟")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("启用", isOn: enabledBinding(rule))
                    .labelsHidden()
                    .toggleStyle(.switch)
                Button("编辑") {
                    isAdding = false
                    editing = rule
                }
                Button("删除", role: .destructive) {
                    store.deleteRule(id: rule.id)
                }
            }
        }
    }

    private func enabledBinding(_ rule: PunchRule) -> Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { value in
                var updated = rule
                updated.enabled = value
                store.updateRule(updated)
            }
        )
    }
}

struct RuleEditorView: View {
    @State var rule: PunchRule
    var isNew: Bool
    var onCancel: () -> Void
    var onSave: (PunchRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "新增打卡规则" : "编辑打卡规则")
                .font(.title2.weight(.semibold))

            Form {
                TextField("名称", text: $rule.name)
                VStack(alignment: .leading, spacing: 10) {
                    Text("截止时间")
                    ClockTimePicker(date: timeBinding)
                        .frame(maxWidth: .infinity)
                }
                Stepper(value: $rule.leadMinutes, in: 1...180) {
                    Text("提前 \(rule.leadMinutes) 分钟开始提醒")
                }
                Stepper(value: $rule.intervalMinutes, in: 1...30) {
                    Text("每隔 \(rule.intervalMinutes) 分钟提醒一次")
                }
                Stepper(value: $rule.graceMinutes, in: 0...60) {
                    Text("到点后继续提醒 \(rule.graceMinutes) 分钟，超时记为缺卡")
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 10) {
                Text("生效星期")
                HStack(spacing: 8) {
                    ForEach(WeekdayFormat.ordered, id: \.id) { item in
                        weekdayChip(item.id, label: item.label)
                    }
                }
            }

            Toggle("启用", isOn: $rule.enabled)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    rule.weekdays.sort()
                    onSave(rule)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.name.isEmpty || rule.weekdays.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 600)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                rule.hour = Calendar.current.component(.hour, from: date)
                rule.minute = Calendar.current.component(.minute, from: date)
            }
        )
    }

    private func weekdayChip(_ id: Int, label: String) -> some View {
        let selected = rule.weekdays.contains(id)
        return Text(label)
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .foregroundStyle(selected ? Color.white : Surface.label)
            .background(
                selected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor).opacity(0.35),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .highPriorityGesture(
                TapGesture().onEnded {
                    if rule.weekdays.contains(id) {
                        rule.weekdays.removeAll { $0 == id }
                    } else {
                        rule.weekdays.append(id)
                    }
                }
            )
    }
}

struct TodayPreviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("按当前规则和单日调整，计算今天实际会跑的场次。到点后才能改打卡状态。")
                .font(.callout)
                .foregroundStyle(Surface.secondary)

            if store.todayOccurrences.isEmpty {
                Text("今天没有打卡安排。")
                    .foregroundStyle(Surface.secondary)
                    .padding(.top, 24)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.todayOccurrences, id: \.rule.id) { occurrence in
                            previewRow(occurrence)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func previewRow(_ occurrence: ReminderLogic.Occurrence) -> some View {
        let status = store.status(for: occurrence)
        let canModify = store.canModify(occurrence)
        return SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(occurrence.rule.name)
                        .font(.headline)
                    Text("提醒窗口 \(format(occurrence.windowStart))–\(format(occurrence.graceEnd))  ·  每 \(occurrence.rule.intervalMinutes) 分钟")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusText(status))
                    .font(.subheadline)
                    .foregroundStyle(statusColor(status))
                if canModify {
                    if status == .confirmed {
                        Button("改为未打卡") {
                            store.unconfirm(ruleId: occurrence.rule.id)
                        }
                        .controlSize(.small)
                    } else {
                        Button("标记已打卡") {
                            store.beginConfirm(occurrence: occurrence)
                            NSApp.activate()
                            openWindow(id: "confirm-punch")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

    private func statusColor(_ status: ReminderLogic.PunchStatus) -> Color {
        switch status {
        case .confirmed: return .green
        case .reminding, .grace: return .orange
        case .expired: return .red
        default: return .secondary
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("外观") {
                Picker("外观", selection: Binding(
                    get: { store.appearance },
                    set: { store.setAppearance($0) }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Picker("字体大小", selection: Binding(
                    get: { store.fontSize },
                    set: { store.setFontSize($0) }
                )) {
                    ForEach(AppFontSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("状态栏显示倒计时", isOn: Binding(
                    get: { store.showMenuBarCountdown },
                    set: { store.setShowMenuBarCountdown($0) }
                ))
                Text("关闭后状态栏只保留图标。提醒期间若开启了自定义文字，仍会显示该文字。")
                    .foregroundStyle(.secondary)

                Text("预览：\(store.menuBarTitle.isEmpty ? "仅图标" : store.menuBarTitle)")
                    .font(.system(size: 13 * store.fontSize.scale, weight: .medium).monospacedDigit())
                    .foregroundStyle(Surface.label)
                Text("菜单栏和设置页会一起变大或变小。")
                    .foregroundStyle(.secondary)
            }

            Section("声音") {
                Toggle("提醒时播放声音", isOn: Binding(
                    get: { store.soundEnabled },
                    set: { store.setSoundEnabled($0) }
                ))
                Picker("提醒音效", selection: Binding(
                    get: { store.alertTone },
                    set: { store.setAlertTone($0) }
                )) {
                    ForEach(AlertTone.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                }
                HStack {
                    Text("选中后会试听，通知横幅也会使用同一音效。")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("试听") {
                        ReminderSound.play(store.alertTone)
                    }
                    .disabled(!store.soundEnabled)
                }
            }

            Section("提醒") {
                Toggle("通知增强", isOn: Binding(
                    get: { store.enhancedAlertEnabled },
                    set: { store.setEnhancedAlertEnabled($0) }
                ))
                Text("开启后用屏幕顶部的自定义窗口提醒打卡，不依赖系统横幅。文案按上班/下班自动切换。")
                    .foregroundStyle(.secondary)

                Toggle("提醒时显示自定义文字", isOn: Binding(
                    get: { store.showReminderText },
                    set: { store.setShowReminderText($0) }
                ))
                TextField("提醒文字", text: Binding(
                    get: { store.reminderText },
                    set: { store.setReminderText($0) }
                ))
                .disabled(!store.showReminderText)
                Text("仅在提醒或宽限期间替换状态栏倒计时，过点后恢复倒计时。")
                    .foregroundStyle(.secondary)

                HStack {
                    Text("按当前打卡类型预览提醒窗口，状态栏图标会闪烁。")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("模拟通知") {
                        store.previewNotification()
                    }
                }
            }

            Section("系统") {
                Toggle("开机自启", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.setLaunchAtLogin($0) }
                ))

                HStack {
                    Text(store.notificationsAuthorized ? "通知权限已开启" : "尚未授权通知")
                        .foregroundStyle(store.notificationsAuthorized ? Color.secondary : Color.orange)
                    Spacer()
                    Button(store.notificationsAuthorized ? "刷新状态" : "请求通知权限") {
                        if store.notificationsAuthorized {
                            store.refreshAuthorizationStatus()
                        } else {
                            store.requestNotificationPermission()
                        }
                    }
                }

                if let lastError = store.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                }

                Text("开机自启需要把「朝夕打卡.app」放到「应用程序」文件夹后再开启。配置保存在本机，改完立即生效。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.refreshAuthorizationStatus()
            store.launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }
}
