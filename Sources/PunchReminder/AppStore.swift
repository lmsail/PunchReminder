import Foundation
import AppKit
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published var rules: [PunchRule]
    @Published var soundEnabled: Bool
    @Published var overrides: [DayOverride]
    @Published var history: [HistoryEntry]
    @Published var dayRuntime: DayRuntime
    @Published var now: Date = Date()
    @Published var launchAtLoginEnabled: Bool = LaunchAtLogin.isEnabled
    @Published var notificationsAuthorized: Bool = false
    @Published var lastError: String?
    @Published var appearance: AppearanceMode
    @Published var fontSize: AppFontSize
    @Published var alertTone: AlertTone
    @Published var enhancedAlertEnabled: Bool
    @Published var showReminderText: Bool
    @Published var showMenuBarCountdown: Bool
    @Published var reminderText: String
    @Published var pendingConfirm: ConfirmPunchRequest?
    @Published var enhancedAlert: EnhancedAlert?
    @Published var menuBarAlertUntil: Date?
    @Published var menuBarIconOn: Bool = true

    private var timer: Timer?
    private var displayTimer: Timer?
    private var blinkTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init() {
        let loaded = Persistence.load()
        rules = PunchRule.normalizedOrder(
            loaded.rules.isEmpty ? PunchRule.makeDefaultRules() : loaded.rules
        )
        soundEnabled = loaded.soundEnabled
        overrides = loaded.overrides
        history = loaded.history
        appearance = loaded.appearance
        fontSize = loaded.fontSize
        alertTone = loaded.alertTone
        enhancedAlertEnabled = loaded.enhancedAlertEnabled
        showReminderText = loaded.showReminderText
        showMenuBarCountdown = loaded.showMenuBarCountdown
        reminderText = loaded.reminderText
        let today = ReminderLogic.dayString(from: Date())
        if let runtime = loaded.dayRuntime, runtime.day == today {
            dayRuntime = runtime
        } else {
            dayRuntime = .empty(day: today)
        }

        NotificationService.shared.onConfirm = { [weak self] ruleId in
            Task { @MainActor in
                self?.confirm(ruleId: ruleId, at: Date())
            }
        }
        NotificationService.shared.onSnooze = { [weak self] ruleId in
            Task { @MainActor in
                self?.snooze(ruleId: ruleId)
            }
        }
        NotificationService.shared.configure()
        ReminderAlertPanelController.shared.onClosed = { [weak self] in
            Task { @MainActor in
                self?.enhancedAlert = nil
                self?.syncBlink()
            }
        }
        requestNotificationPermission()
        startTimer()
        startDisplayTimer()
        observeWake()
        rotateDayIfNeeded(at: Date())
        tick(forceInWindow: true)
        syncBlink()
    }

    var todayOccurrences: [ReminderLogic.Occurrence] {
        ReminderLogic.effectiveOccurrences(rules: rules, overrides: overrides, on: now)
    }

    var conflicts: [String] {
        ReminderLogic.duplicateTimeConflicts(rules: rules)
    }

    var isMenuBarAlerting: Bool {
        if enhancedAlert != nil {
            return true
        }
        if let until = menuBarAlertUntil, now < until {
            return true
        }
        return todayOccurrences.contains { occurrence in
            let current = status(for: occurrence)
            return current == .reminding || current == .grace
        }
    }

    var menuBarTitle: String {
        let countdown: String
        if let clockOut = ReminderLogic.clockOutOccurrence(from: todayOccurrences) {
            if now >= clockOut.deadline {
                countdown = "已下班"
            } else {
                countdown = ReminderLogic.countdownText(to: clockOut.deadline, now: now)
            }
        } else {
            countdown = "休息"
        }
        return ReminderLogic.menuBarDisplayTitle(
            countdown: countdown,
            isAlerting: isMenuBarAlerting,
            showReminderText: showReminderText,
            showMenuBarCountdown: showMenuBarCountdown,
            reminderText: reminderText
        )
    }

    func canModify(_ occurrence: ReminderLogic.Occurrence) -> Bool {
        ReminderLogic.canModifyStatus(deadline: occurrence.deadline, now: now)
    }

    func canModify(entry: HistoryEntry) -> Bool {
        let today = ReminderLogic.dayString(from: now)
        if entry.day < today {
            return true
        }
        if entry.day > today {
            return false
        }
        if let occurrence = todayOccurrences.first(where: { $0.rule.id == entry.ruleId }) {
            return canModify(occurrence)
        }
        guard let dayDate = ReminderLogic.date(fromDay: entry.day),
              let deadline = Calendar.current.date(
                  bySettingHour: entry.deadlineHour,
                  minute: entry.deadlineMinute,
                  second: 0,
                  of: dayDate
              ) else {
            return false
        }
        return ReminderLogic.canModifyStatus(deadline: deadline, now: now)
    }

    func status(for occurrence: ReminderLogic.Occurrence) -> ReminderLogic.PunchStatus {
        ReminderLogic.status(for: occurrence, runtime: dayRuntime, now: now)
    }

    func confirmedAt(for occurrence: ReminderLogic.Occurrence) -> Date? {
        let day = ReminderLogic.dayString(from: occurrence.deadline)
        return history.first { $0.day == day && $0.ruleId == occurrence.rule.id }?.confirmedAt
    }

    func confirm(ruleId: UUID, at confirmedAt: Date) {
        rotateDayIfNeeded(at: Date())
        guard let occurrence = todayOccurrences.first(where: { $0.rule.id == ruleId }),
              ReminderLogic.canModifyStatus(deadline: occurrence.deadline, now: Date()) else {
            return
        }
        if !dayRuntime.confirmedRuleIds.contains(ruleId) {
            dayRuntime.confirmedRuleIds.append(ruleId)
        }
        dayRuntime.snoozeUntil[ruleId.uuidString] = nil
        upsertHistory(
            occurrence: occurrence,
            confirmedAt: confirmedAt,
            missed: false,
            overwriteConfirmed: true
        )
        persist()
        objectWillChange.send()
        dismissEnhancedAlert()
    }

    func unconfirm(ruleId: UUID) {
        rotateDayIfNeeded(at: Date())
        guard let occurrence = todayOccurrences.first(where: { $0.rule.id == ruleId }),
              ReminderLogic.canModifyStatus(deadline: occurrence.deadline, now: Date()) else {
            return
        }
        dayRuntime.confirmedRuleIds.removeAll { $0 == ruleId }
        upsertHistory(
            occurrence: occurrence,
            confirmedAt: nil,
            missed: true,
            overwriteConfirmed: true
        )
        persist()
        objectWillChange.send()
    }

    func setPunched(entry: HistoryEntry, punched: Bool, at confirmedAt: Date? = nil) {
        guard canModify(entry: entry) else { return }
        let today = ReminderLogic.dayString(from: Date())
        if entry.day == today {
            if punched {
                confirm(ruleId: entry.ruleId, at: confirmedAt ?? Date())
            } else {
                unconfirm(ruleId: entry.ruleId)
            }
            return
        }
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[index].confirmedAt = punched ? (confirmedAt ?? Date()) : nil
        history[index].missed = !punched
        persist()
    }

    func setAppearance(_ mode: AppearanceMode) {
        appearance = mode
        appearance.apply()
        persist()
    }

    func setFontSize(_ size: AppFontSize) {
        fontSize = size
        persist()
    }

    func beginConfirm(occurrence: ReminderLogic.Occurrence) {
        let now = Date()
        let bounds = ReminderLogic.punchTimeBounds(on: occurrence.deadline, now: now)
        let suggested = ReminderLogic.suggestedPunchTime(
            deadline: occurrence.deadline,
            earliest: bounds.earliest,
            latest: bounds.latest
        )
        pendingConfirm = ConfirmPunchRequest(
            ruleId: occurrence.rule.id,
            historyId: nil,
            title: occurrence.rule.name,
            subtitle: "\(occurrence.rule.name) 截止 \(occurrence.rule.timeText)",
            day: bounds.earliest,
            defaultDate: suggested,
            pickerDate: ReminderLogic.pickerPunchTime(
                now: now,
                day: bounds.earliest,
                earliest: bounds.earliest,
                latest: bounds.latest
            ),
            latest: bounds.latest,
            shortcutTitle: ReminderLogic.suggestedPunchTitle(suggested: suggested, deadline: occurrence.deadline)
        )
    }

    func beginConfirm(entry: HistoryEntry) {
        let now = Date()
        let day = ReminderLogic.date(fromDay: entry.day) ?? now
        let bounds = ReminderLogic.punchTimeBounds(on: day, now: now)
        let deadline = Calendar.current.date(
            bySettingHour: entry.deadlineHour,
            minute: entry.deadlineMinute,
            second: 0,
            of: day
        ) ?? bounds.latest
        let suggested = ReminderLogic.suggestedPunchTime(
            deadline: deadline,
            earliest: bounds.earliest,
            latest: bounds.latest
        )
        pendingConfirm = ConfirmPunchRequest(
            ruleId: entry.ruleId,
            historyId: entry.id,
            title: entry.ruleName,
            subtitle: "\(entry.day) \(entry.ruleName) 截止 \(entry.deadlineText)",
            day: bounds.earliest,
            defaultDate: suggested,
            pickerDate: ReminderLogic.pickerPunchTime(
                now: now,
                day: bounds.earliest,
                earliest: bounds.earliest,
                latest: bounds.latest
            ),
            latest: bounds.latest,
            shortcutTitle: ReminderLogic.suggestedPunchTitle(suggested: suggested, deadline: deadline)
        )
    }

    func completePendingConfirm(at date: Date) {
        guard let pending = pendingConfirm else { return }
        if let historyId = pending.historyId,
           let entry = history.first(where: { $0.id == historyId }) {
            setPunched(entry: entry, punched: true, at: date)
        } else {
            confirm(ruleId: pending.ruleId, at: date)
        }
        pendingConfirm = nil
    }

    func cancelPendingConfirm() {
        pendingConfirm = nil
    }

    func snooze(ruleId: UUID) {
        rotateDayIfNeeded(at: Date())
        guard let occurrence = todayOccurrences.first(where: { $0.rule.id == ruleId }) else { return }
        let interval = TimeInterval(max(occurrence.rule.intervalMinutes, 1) * 60)
        dayRuntime.snoozeUntil[ruleId.uuidString] = Date().addingTimeInterval(interval)
        persist()
        dismissEnhancedAlert()
    }

    func togglePaused() {
        dayRuntime.paused.toggle()
        persist()
    }

    func saveRules(_ newRules: [PunchRule]) {
        rules = newRules
        persist()
        tick(forceInWindow: true)
    }

    func addRule(_ rule: PunchRule) {
        let index = rules.firstIndex { $0.timeMinutes > rule.timeMinutes } ?? rules.count
        rules.insert(rule, at: index)
        reindexRules()
        persist()
    }

    func updateRule(_ rule: PunchRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
        tick(forceInWindow: true)
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        reindexRules()
        persist()
    }

    func moveRules(from offsets: IndexSet, to destination: Int) {
        rules.move(fromOffsets: offsets, toOffset: destination)
        reindexRules()
        persist()
    }

    private func reindexRules() {
        for index in rules.indices {
            rules[index].sortIndex = index
        }
    }

    func addOverride(_ override: DayOverride) {
        overrides.removeAll { existing in
            existing.day == override.day
                && existing.kind == override.kind
                && existing.ruleId == override.ruleId
        }
        overrides.append(override)
        persist()
        tick(forceInWindow: true)
    }

    func deleteOverride(id: UUID) {
        overrides.removeAll { $0.id == id }
        persist()
        tick(forceInWindow: true)
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        persist()
    }

    func setAlertTone(_ tone: AlertTone) {
        alertTone = tone
        persist()
        if soundEnabled {
            ReminderSound.play(tone)
        }
    }

    func setEnhancedAlertEnabled(_ enabled: Bool) {
        enhancedAlertEnabled = enabled
        persist()
        if !enabled {
            dismissEnhancedAlert()
        }
    }

    func setShowReminderText(_ enabled: Bool) {
        showReminderText = enabled
        persist()
    }

    func setShowMenuBarCountdown(_ enabled: Bool) {
        showMenuBarCountdown = enabled
        persist()
    }

    func setReminderText(_ text: String) {
        reminderText = text
        persist()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            lastError = nil
        } catch {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            lastError = "开机启动设置失败：\(error.localizedDescription)。请先把应用放到「应用程序」文件夹。"
        }
    }

    func refreshAuthorizationStatus() {
        NotificationService.shared.authorizationStatus { [weak self] granted in
            Task { @MainActor in
                self?.notificationsAuthorized = granted
            }
        }
    }

    func requestNotificationPermission() {
        NotificationService.shared.requestAuthorization { [weak self] granted in
            Task { @MainActor in
                self?.notificationsAuthorized = granted
                if !granted {
                    self?.lastError = "未获得通知权限，请在「系统设置 › 通知」中允许「朝夕打卡」。"
                }
            }
        }
    }

    func previewNotification() {
        lastError = nil
        if soundEnabled {
            ReminderSound.play(alertTone)
        }
        now = Date()
        if enhancedAlertEnabled {
            let sample = previewAlertSample()
            presentEnhancedAlert(
                ruleName: sample.ruleName,
                title: ReminderLogic.enhancedAlertTitle(ruleName: sample.ruleName),
                body: ReminderLogic.enhancedAlertBody(
                    ruleName: sample.ruleName,
                    deadline: sample.deadline,
                    graceEnd: sample.graceEnd,
                    now: now
                ),
                ruleId: nil
            )
        } else {
            menuBarAlertUntil = Date().addingTimeInterval(12)
            syncBlink()
            NotificationService.shared.requestAuthorization { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.notificationsAuthorized = granted
                    guard granted else {
                        self.lastError = "未获得通知权限。可开启「通知增强」用自定义窗口提醒。"
                        return
                    }
                    NotificationService.shared.sendPreview(
                        soundEnabled: self.soundEnabled,
                        tone: self.alertTone
                    ) { warning in
                        self.lastError = warning
                    }
                }
            }
        }
    }

    func presentEnhancedAlert(ruleName: String, title: String, body: String, ruleId: UUID?) {
        enhancedAlert = EnhancedAlert(ruleName: ruleName, title: title, body: body, ruleId: ruleId)
        menuBarAlertUntil = nil
        syncBlink()
        ReminderAlertPanelController.shared.show(store: self)
    }

    func dismissEnhancedAlert() {
        enhancedAlert = nil
        menuBarAlertUntil = nil
        ReminderAlertPanelController.shared.hide()
        syncBlink()
    }

    func snoozeEnhancedAlert() {
        if let ruleId = enhancedAlert?.ruleId {
            snooze(ruleId: ruleId)
            return
        }
        dismissEnhancedAlert()
    }

    func confirmEnhancedAlert() {
        guard let ruleId = enhancedAlert?.ruleId,
              let occurrence = todayOccurrences.first(where: { $0.rule.id == ruleId }) else {
            dismissEnhancedAlert()
            return
        }
        beginConfirm(occurrence: occurrence)
        dismissEnhancedAlert()
        NotificationCenter.default.post(name: .punchReminderOpenConfirm, object: nil)
    }

    func tick(forceInWindow: Bool = false) {
        now = Date()
        rotateDayIfNeeded(at: now)
        pruneHistory()

        for occurrence in todayOccurrences {
            if ReminderLogic.shouldFire(
                occurrence: occurrence,
                runtime: dayRuntime,
                now: now,
                forceInWindow: forceInWindow
            ) {
                if enhancedAlertEnabled {
                    presentEnhancedAlert(
                        ruleName: occurrence.rule.name,
                        title: ReminderLogic.enhancedAlertTitle(ruleName: occurrence.rule.name),
                        body: NotificationService.alertBody(for: occurrence, now: now),
                        ruleId: occurrence.rule.id
                    )
                } else {
                    NotificationService.shared.send(
                        occurrence: occurrence,
                        soundEnabled: soundEnabled,
                        tone: alertTone
                    )
                }
                if soundEnabled {
                    ReminderSound.play(alertTone)
                }
                dayRuntime.lastFiredAt[occurrence.rule.id.uuidString] = now
                persist()
            }

            if now >= occurrence.graceEnd, !dayRuntime.confirmedRuleIds.contains(occurrence.rule.id) {
                upsertHistory(occurrence: occurrence, confirmedAt: nil, missed: true)
            }
        }
    }

    private func rotateDayIfNeeded(at date: Date) {
        let today = ReminderLogic.dayString(from: date)
        guard dayRuntime.day != today else { return }

        let previousDay = dayRuntime.day
        if let previousDate = ReminderLogic.date(fromDay: previousDay) {
            let leftover = ReminderLogic.effectiveOccurrences(
                rules: rules,
                overrides: overrides,
                on: previousDate
            )
            for occurrence in leftover where !dayRuntime.confirmedRuleIds.contains(occurrence.rule.id) {
                upsertHistory(
                    occurrence: occurrence,
                    confirmedAt: nil,
                    missed: true,
                    day: previousDay
                )
            }
        }

        dayRuntime = .empty(day: today)
        persist()
    }

    private func upsertHistory(
        occurrence: ReminderLogic.Occurrence,
        confirmedAt: Date?,
        missed: Bool,
        day: String? = nil,
        overwriteConfirmed: Bool = false
    ) {
        let dayKey = day ?? ReminderLogic.dayString(from: occurrence.deadline)
        if let index = history.firstIndex(where: { $0.day == dayKey && $0.ruleId == occurrence.rule.id }) {
            if history[index].confirmedAt != nil, !overwriteConfirmed {
                return
            }
            if missed && confirmedAt == nil && history[index].missed && history[index].confirmedAt == nil {
                return
            }
            history[index].ruleName = occurrence.rule.name
            history[index].deadlineHour = occurrence.deadlineHour
            history[index].deadlineMinute = occurrence.deadlineMinute
            history[index].confirmedAt = confirmedAt
            history[index].missed = missed && confirmedAt == nil
        } else {
            history.insert(
                HistoryEntry(
                    id: UUID(),
                    day: dayKey,
                    ruleId: occurrence.rule.id,
                    ruleName: occurrence.rule.name,
                    deadlineHour: occurrence.deadlineHour,
                    deadlineMinute: occurrence.deadlineMinute,
                    confirmedAt: confirmedAt,
                    missed: missed && confirmedAt == nil
                ),
                at: 0
            )
        }
        persist()
    }

    private func pruneHistory() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let cutoffDay = ReminderLogic.dayString(from: cutoff)
        history.removeAll { $0.day < cutoffDay }
        overrides.removeAll { override in
            guard let date = ReminderLogic.date(fromDay: override.day) else { return false }
            return date < Calendar.current.startOfDay(for: cutoff)
        }
    }

    private func persist() {
        Persistence.save(
            PersistedState(
                rules: rules,
                soundEnabled: soundEnabled,
                overrides: overrides,
                history: history,
                dayRuntime: dayRuntime,
                appearance: appearance,
                fontSize: fontSize,
                alertTone: alertTone,
                enhancedAlertEnabled: enhancedAlertEnabled,
                showReminderText: showReminderText,
                showMenuBarCountdown: showMenuBarCountdown,
                reminderText: reminderText
            )
        )
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.rotateDayIfNeeded(at: Date())
                self?.syncBlink()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func previewAlertSample() -> (ruleName: String, deadline: Date, graceEnd: Date) {
        if let current = todayOccurrences.first(where: { occurrence in
            let current = status(for: occurrence)
            return current == .reminding || current == .grace
        }) {
            return (current.rule.name, current.deadline, current.graceEnd)
        }
        if let next = ReminderLogic.nextOccurrence(from: todayOccurrences, runtime: dayRuntime, now: now) {
            return (next.rule.name, next.deadline, next.graceEnd)
        }
        if let first = todayOccurrences.first {
            return (first.rule.name, first.deadline, first.graceEnd)
        }
        let deadline = now.addingTimeInterval(20 * 60)
        return ("上班", deadline, deadline.addingTimeInterval(10 * 60))
    }

    private func syncBlink() {
        if isMenuBarAlerting {
            if blinkTimer == nil {
                menuBarIconOn = true
                let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.menuBarIconOn.toggle()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                blinkTimer = timer
            }
        } else if blinkTimer != nil {
            blinkTimer?.invalidate()
            blinkTimer = nil
            menuBarIconOn = true
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick(forceInWindow: true)
            }
        }
    }
}
