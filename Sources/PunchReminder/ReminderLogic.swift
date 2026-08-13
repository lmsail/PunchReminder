import Foundation

enum ReminderLogic {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    struct Occurrence: Equatable {
        var rule: PunchRule
        var deadline: Date
        var windowStart: Date

        var deadlineHour: Int {
            Calendar.current.component(.hour, from: deadline)
        }

        var deadlineMinute: Int {
            Calendar.current.component(.minute, from: deadline)
        }

        var graceEnd: Date {
            deadline.addingTimeInterval(TimeInterval(max(rule.graceMinutes, 0) * 60))
        }
    }

    enum PunchStatus: Equatable {
        case upcoming
        case reminding
        case snoozed
        case confirmed
        case grace
        case expired
        case paused
        case skipped
    }

    static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func date(fromDay day: String, calendar: Calendar = .current) -> Date? {
        dayFormatter.date(from: day).flatMap { calendar.startOfDay(for: $0) }
    }

    static func effectiveOccurrences(
        rules: [PunchRule],
        overrides: [DayOverride],
        on date: Date,
        calendar: Calendar = .current
    ) -> [Occurrence] {
        let day = dayString(from: date)
        if overrides.contains(where: { $0.day == day && $0.kind == .skipDay }) {
            return []
        }

        let weekday = calendar.component(.weekday, from: date)
        var result: [Occurrence] = []

        for rule in rules where rule.enabled && rule.weekdays.contains(weekday) {
            if overrides.contains(where: { $0.day == day && $0.kind == .skipRule && $0.ruleId == rule.id }) {
                continue
            }

            var hour = rule.hour
            var minute = rule.minute
            if let replacement = overrides.first(where: {
                $0.day == day && $0.kind == .replaceTime && $0.ruleId == rule.id
            }) {
                hour = replacement.hour ?? hour
                minute = replacement.minute ?? minute
            }

            guard let deadline = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else {
                continue
            }
            let windowStart = deadline.addingTimeInterval(TimeInterval(-max(rule.leadMinutes, 1) * 60))
            result.append(Occurrence(rule: rule, deadline: deadline, windowStart: windowStart))
        }

        return result.sorted { $0.deadline < $1.deadline }
    }

    static func canModifyStatus(deadline: Date, now: Date) -> Bool {
        now >= deadline
    }

    static func clockOutOccurrence(from occurrences: [Occurrence]) -> Occurrence? {
        occurrences
            .filter { $0.deadlineHour * 60 + $0.deadlineMinute >= 12 * 60 }
            .max { $0.deadline < $1.deadline }
    }

    static func countdownText(to deadline: Date, now: Date) -> String {
        let remaining = max(Int(deadline.timeIntervalSince(now).rounded(.down)), 0)
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if remaining == 0 {
            return "00秒"
        }
        var parts: [String] = []
        if hours > 0 {
            parts.append(String(format: "%02d时", hours))
            parts.append(String(format: "%02d分", minutes))
        } else if minutes > 0 {
            parts.append(String(format: "%02d分", minutes))
        }
        parts.append(String(format: "%02d秒", seconds))
        return parts.joined()
    }

    static func isClockOutName(_ name: String) -> Bool {
        name.contains("下班")
    }

    static func punchKindLabel(ruleName: String) -> String {
        isClockOutName(ruleName) ? "下班" : "上班"
    }

    static func enhancedAlertTitle(ruleName: String) -> String {
        "\(ruleName)打卡"
    }

    static func enhancedAlertBody(
        ruleName: String,
        deadline: Date,
        graceEnd: Date,
        now: Date
    ) -> String {
        let kind = punchKindLabel(ruleName: ruleName)
        let remainingToDeadline = max(Int(deadline.timeIntervalSince(now) / 60), 0)
        let remainingToGrace = max(Int(graceEnd.timeIntervalSince(now) / 60), 0)
        if now >= deadline {
            return remainingToGrace == 0
                ? "\(kind)卡宽限已到，将记为缺卡"
                : "\(kind)卡已过截止，还有 \(remainingToGrace) 分钟，超时记为缺卡"
        }
        return remainingToDeadline == 0
            ? "\(kind)截止时间到了，请立刻打卡"
            : "还有 \(remainingToDeadline) 分钟，请记得打\(kind)卡"
    }

    static func lateText(deadline: Date, now: Date, clockOut: Bool = false) -> String {
        let late = max(Int(now.timeIntervalSince(deadline).rounded(.down)), 0)
        let hours = late / 3600
        let minutes = (late % 3600) / 60
        let prefix = clockOut ? "已过点" : "已迟到"
        if hours > 0 {
            return prefix + String(format: "%02d时%02d分", hours, minutes)
        }
        return prefix + String(format: "%02d分", minutes)
    }

    static func punchTimeBounds(on day: Date, now: Date, calendar: Calendar = .current) -> (earliest: Date, latest: Date) {
        let start = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        let endOfDay = nextDay.addingTimeInterval(-60)
        if now >= start && now < nextDay {
            return (start, now)
        }
        return (start, endOfDay)
    }

    /// 快捷补记一律用截止时间，手动选时分仍可改。
    static func suggestedPunchTime(
        deadline: Date,
        earliest: Date,
        latest: Date
    ) -> Date {
        min(max(deadline, earliest), latest)
    }

    /// 手动选择默认显示当前时分，落在当天可补记范围内。
    static func pickerPunchTime(
        now: Date,
        day: Date,
        earliest: Date,
        latest: Date,
        calendar: Calendar = .current
    ) -> Date {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? now
        return min(max(candidate, earliest), latest)
    }

    static func suggestedPunchTitle(suggested: Date, deadline: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: suggested)
        if abs(suggested.timeIntervalSince(deadline)) < 60 {
            return "按准时 \(time) 打卡"
        }
        return "按现在 \(time) 打卡"
    }

    static func menuBarDisplayTitle(
        countdown: String,
        isAlerting: Bool,
        showReminderText: Bool,
        reminderText: String
    ) -> String {
        if isAlerting && showReminderText && !reminderText.isEmpty {
            return reminderText
        }
        return countdown
    }

    static func status(
        for occurrence: Occurrence,
        runtime: DayRuntime,
        now: Date
    ) -> PunchStatus {
        if runtime.confirmedRuleIds.contains(occurrence.rule.id) {
            return .confirmed
        }
        if now >= occurrence.graceEnd {
            return .expired
        }
        if runtime.paused {
            return .paused
        }
        if now < occurrence.windowStart {
            return .upcoming
        }
        if let snoozeUntil = runtime.snoozeUntil[occurrence.rule.id.uuidString], snoozeUntil > now {
            return .snoozed
        }
        if now >= occurrence.deadline {
            return .grace
        }
        return .reminding
    }

    static func shouldFire(
        occurrence: Occurrence,
        runtime: DayRuntime,
        now: Date,
        forceInWindow: Bool
    ) -> Bool {
        let current = status(for: occurrence, runtime: runtime, now: now)
        guard current == .reminding || current == .grace else {
            return false
        }

        if forceInWindow {
            if let last = runtime.lastFiredAt[occurrence.rule.id.uuidString],
               now.timeIntervalSince(last) < 30 {
                return false
            }
            return true
        }

        let interval = TimeInterval(max(occurrence.rule.intervalMinutes, 1) * 60)
        guard let last = runtime.lastFiredAt[occurrence.rule.id.uuidString] else {
            return true
        }
        return now >= last.addingTimeInterval(interval)
    }

    static func nextOccurrence(
        from occurrences: [Occurrence],
        runtime: DayRuntime,
        now: Date
    ) -> Occurrence? {
        occurrences.first { occurrence in
            let current = status(for: occurrence, runtime: runtime, now: now)
            return current == .upcoming || current == .reminding || current == .grace || current == .snoozed || current == .paused
        }
    }

    /// 同一天同一时刻有多条启用规则才视为冲突；一天多次打卡是合法的。
    static func duplicateTimeConflicts(rules: [PunchRule]) -> [String] {
        var messages: [String] = []
        for weekday in WeekdayFormat.ordered {
            let enabled = rules.filter { $0.enabled && $0.weekdays.contains(weekday.id) }
            let grouped = Dictionary(grouping: enabled, by: \.timeMinutes)
            for minutes in grouped.keys.sorted() {
                guard let items = grouped[minutes], items.count >= 2 else { continue }
                let names = items.map(\.name).joined(separator: "、")
                let time = String(format: "%02d:%02d", minutes / 60, minutes % 60)
                messages.append("周\(weekday.label)：\(names) 都在 \(time)")
            }
        }
        return messages
    }
}
