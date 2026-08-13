import Foundation

enum ExpectationFailure: Error {
    case failed(String)
}

func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ExpectationFailure.failed(message)
    }
}

func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return Calendar.current.date(from: components)!
}

@main
struct LogicTests {
    static func main() throws {
        let rules = PunchRule.makeDefaultRules()

        let wednesday = date(year: 2026, month: 8, day: 12, hour: 10)
        let wedOcc = ReminderLogic.effectiveOccurrences(rules: rules, overrides: [], on: wednesday)
        try expect(wedOcc.map(\.rule.name) == ["上班", "晚下班"], "周三应为上班+晚下班，实际 \(wedOcc.map(\.rule.name))")

        let monday = date(year: 2026, month: 8, day: 10, hour: 10)
        let monOcc = ReminderLogic.effectiveOccurrences(rules: rules, overrides: [], on: monday)
        try expect(monOcc.map(\.rule.name) == ["上班", "下班"], "周一应为上班+下班，实际 \(monOcc.map(\.rule.name))")

        let saturday = date(year: 2026, month: 8, day: 15, hour: 10)
        let satOcc = ReminderLogic.effectiveOccurrences(rules: rules, overrides: [], on: saturday)
        try expect(satOcc.isEmpty, "周六应无提醒")

        let morning = wedOcc.first { $0.rule.name == "上班" }!
        try expect(
            Calendar.current.component(.hour, from: morning.windowStart) == 8
                && Calendar.current.component(.minute, from: morning.windowStart) == 40,
            "上班窗口应 08:40 开始"
        )

        let atNine = date(year: 2026, month: 8, day: 12, hour: 9, minute: 0)
        let beforeNine = date(year: 2026, month: 8, day: 12, hour: 8, minute: 50)
        let duringGrace = date(year: 2026, month: 8, day: 12, hour: 9, minute: 5)
        let afterGrace = date(year: 2026, month: 8, day: 12, hour: 9, minute: 10)
        let runtime = DayRuntime.empty(day: "2026-08-12")
        try expect(
            ReminderLogic.status(for: morning, runtime: runtime, now: beforeNine) == .reminding,
            "8:50 应处于提醒中"
        )
        try expect(
            ReminderLogic.status(for: morning, runtime: runtime, now: atNine) == .grace,
            "9:00 未打卡应进入宽限"
        )
        try expect(
            ReminderLogic.status(for: morning, runtime: runtime, now: duringGrace) == .grace,
            "9:05 未打卡应仍在宽限"
        )
        try expect(
            ReminderLogic.status(for: morning, runtime: runtime, now: afterGrace) == .expired,
            "9:10 应记为缺卡"
        )
        try expect(
            ReminderLogic.shouldFire(occurrence: morning, runtime: runtime, now: beforeNine, forceInWindow: false),
            "窗口内首次应立即提醒"
        )
        try expect(
            ReminderLogic.shouldFire(occurrence: morning, runtime: runtime, now: duringGrace, forceInWindow: false),
            "宽限内应继续提醒"
        )
        try expect(
            !ReminderLogic.shouldFire(occurrence: morning, runtime: runtime, now: afterGrace, forceInWindow: false),
            "超过宽限不应再提醒"
        )

        try expect(
            !ReminderLogic.canModifyStatus(deadline: morning.deadline, now: beforeNine),
            "到点前不可改状态"
        )
        try expect(
            ReminderLogic.canModifyStatus(deadline: morning.deadline, now: atNine),
            "到点后可改状态"
        )

        let clockOut = ReminderLogic.clockOutOccurrence(from: wedOcc)!
        try expect(clockOut.rule.name == "晚下班", "周三下班倒计时应对晚下班")
        try expect(
            ReminderLogic.countdownText(to: clockOut.deadline, now: date(year: 2026, month: 8, day: 12, hour: 20, minute: 0)) == "01时00分00秒",
            "整点倒计时应保留 00分00秒"
        )
        try expect(
            ReminderLogic.countdownText(
                to: clockOut.deadline,
                now: date(year: 2026, month: 8, day: 12, hour: 11, minute: 59, second: 16)
            ) == "09时00分44秒",
            "分钟为 0 时应显示 09时00分44秒"
        )
        try expect(
            ReminderLogic.lateText(
                deadline: date(year: 2026, month: 8, day: 12, hour: 9, minute: 0),
                now: date(year: 2026, month: 8, day: 12, hour: 9, minute: 8)
            ) == "已迟到08分",
            "不足一小时只显示分钟"
        )
        try expect(
            ReminderLogic.lateText(
                deadline: date(year: 2026, month: 8, day: 12, hour: 9, minute: 0),
                now: date(year: 2026, month: 8, day: 12, hour: 10, minute: 5)
            ) == "已迟到01时05分",
            "超过一小时应显示时和分"
        )
        try expect(
            ReminderLogic.lateText(
                deadline: date(year: 2026, month: 8, day: 12, hour: 12, minute: 0),
                now: date(year: 2026, month: 8, day: 12, hour: 14, minute: 9),
                clockOut: true
            ) == "已过点02时09分",
            "下班缺卡应显示已过点而不是迟到"
        )
        try expect(
            ReminderLogic.isClockOutName("中午下班") && !ReminderLogic.isClockOutName("下午上班"),
            "应按名称区分下班卡和上班卡"
        )

        var confirmed = runtime
        confirmed.confirmedRuleIds = [morning.rule.id]
        try expect(
            ReminderLogic.status(for: morning, runtime: confirmed, now: beforeNine) == .confirmed,
            "确认后应停止"
        )

        let skip = DayOverride(id: UUID(), day: "2026-08-12", kind: .skipDay, ruleId: nil, hour: nil, minute: nil)
        try expect(
            ReminderLogic.effectiveOccurrences(rules: rules, overrides: [skip], on: wednesday).isEmpty,
            "请假当天应无提醒"
        )

        let lateRule = rules.first { $0.name == "晚下班" }!
        let replace = DayOverride(
            id: UUID(),
            day: "2026-08-10",
            kind: .replaceTime,
            ruleId: rules.first { $0.name == "下班" }!.id,
            hour: 21,
            minute: 0
        )
        let replaced = ReminderLogic.effectiveOccurrences(rules: rules, overrides: [replace], on: monday)
        let off = replaced.first { $0.rule.name == "下班" }!
        try expect(off.deadlineHour == 21 && off.deadlineMinute == 0, "单日改点应为 21:00")

        var fourCards = rules
        fourCards.append(
            PunchRule(
                id: UUID(),
                name: "中午下班",
                hour: 12,
                minute: 0,
                weekdays: [2, 3, 4, 5, 6],
                leadMinutes: 5,
                intervalMinutes: 2,
                graceMinutes: 10,
                enabled: true
            )
        )
        fourCards.append(
            PunchRule(
                id: UUID(),
                name: "下午上班",
                hour: 13,
                minute: 30,
                weekdays: [2, 3, 4, 5, 6],
                leadMinutes: 20,
                intervalMinutes: 2,
                graceMinutes: 10,
                enabled: true
            )
        )
        try expect(
            ReminderLogic.duplicateTimeConflicts(rules: fourCards).isEmpty,
            "一天四次卡不应报冲突"
        )

        var duplicate = rules
        duplicate[1].hour = 9
        duplicate[1].minute = 0
        duplicate[1].weekdays = [2, 3, 4, 5, 6]
        let messages = ReminderLogic.duplicateTimeConflicts(rules: duplicate)
        try expect(messages.contains { $0.contains("09:00") }, "同一时刻多条规则应检出冲突")

        var unordered = rules
        unordered[0].sortIndex = -1
        unordered[1].sortIndex = -1
        unordered[2].sortIndex = -1
        unordered.swapAt(0, 2)
        try expect(
            PunchRule.normalizedOrder(unordered).map(\.name) == ["上班", "下班", "晚下班"],
            "缺序号时应按时间正序"
        )
        var custom = PunchRule.normalizedOrder(rules)
        custom.swapAt(0, 2)
        custom[0].sortIndex = 0
        custom[1].sortIndex = 1
        custom[2].sortIndex = 2
        try expect(
            PunchRule.normalizedOrder(custom).map(\.name) == ["晚下班", "下班", "上班"],
            "已拖拽排序应保留手动顺序"
        )

        let morningDeadline = date(year: 2026, month: 8, day: 12, hour: 9, minute: 0)
        let afterMorning = date(year: 2026, month: 8, day: 12, hour: 9, minute: 30)
        let morningBounds = ReminderLogic.punchTimeBounds(on: morningDeadline, now: afterMorning)
        let morningSuggested = ReminderLogic.suggestedPunchTime(
            deadline: morningDeadline,
            earliest: morningBounds.earliest,
            latest: morningBounds.latest
        )
        try expect(
            Calendar.current.component(.hour, from: morningSuggested) == 9
                && Calendar.current.component(.minute, from: morningSuggested) == 0,
            "上班过点应建议准时 09:00"
        )
        try expect(
            ReminderLogic.suggestedPunchTitle(suggested: morningSuggested, deadline: morningDeadline) == "按准时 09:00 打卡",
            "上班快捷文案应为准时"
        )

        let eveningDeadline = date(year: 2026, month: 8, day: 12, hour: 18, minute: 0)
        let afterEvening = date(year: 2026, month: 8, day: 12, hour: 18, minute: 32)
        let eveningBounds = ReminderLogic.punchTimeBounds(on: eveningDeadline, now: afterEvening)
        let eveningSuggested = ReminderLogic.suggestedPunchTime(
            deadline: eveningDeadline,
            earliest: eveningBounds.earliest,
            latest: eveningBounds.latest
        )
        try expect(
            Calendar.current.component(.hour, from: eveningSuggested) == 18
                && Calendar.current.component(.minute, from: eveningSuggested) == 0,
            "下班过点应建议截止时间"
        )
        try expect(
            ReminderLogic.suggestedPunchTitle(suggested: eveningSuggested, deadline: eveningDeadline) == "按准时 18:00 打卡",
            "下班快捷文案应为准时"
        )

        let noonDeadline = date(year: 2026, month: 8, day: 12, hour: 12, minute: 0)
        let afterNoon = date(year: 2026, month: 8, day: 12, hour: 14, minute: 18)
        let noonBounds = ReminderLogic.punchTimeBounds(on: noonDeadline, now: afterNoon)
        let noonSuggested = ReminderLogic.suggestedPunchTime(
            deadline: noonDeadline,
            earliest: noonBounds.earliest,
            latest: noonBounds.latest
        )
        try expect(
            Calendar.current.component(.hour, from: noonSuggested) == 12
                && Calendar.current.component(.minute, from: noonSuggested) == 0,
            "中午下班补记应建议 12:00 而不是当前时间"
        )
        let noonPicker = ReminderLogic.pickerPunchTime(
            now: afterNoon,
            day: noonBounds.earliest,
            earliest: noonBounds.earliest,
            latest: noonBounds.latest
        )
        try expect(
            Calendar.current.component(.hour, from: noonPicker) == 14
                && Calendar.current.component(.minute, from: noonPicker) == 18,
            "手动选择应显示当前时间 14:18"
        )

        let pastEvening = date(year: 2026, month: 8, day: 11, hour: 18, minute: 0)
        let nextMorning = date(year: 2026, month: 8, day: 12, hour: 10, minute: 0)
        let pastBounds = ReminderLogic.punchTimeBounds(on: pastEvening, now: nextMorning)
        let pastSuggested = ReminderLogic.suggestedPunchTime(
            deadline: pastEvening,
            earliest: pastBounds.earliest,
            latest: pastBounds.latest
        )
        try expect(
            Calendar.current.component(.hour, from: pastSuggested) == 18
                && Calendar.current.component(.minute, from: pastSuggested) == 0,
            "跨日补记下应建议截止时间"
        )

        try expect(
            ReminderLogic.menuBarDisplayTitle(
                countdown: "06时50分21秒",
                isAlerting: true,
                showReminderText: true,
                showMenuBarCountdown: true,
                reminderText: "该打卡了"
            ) == "该打卡了",
            "提醒期间应显示自定义文字"
        )
        try expect(
            ReminderLogic.menuBarDisplayTitle(
                countdown: "06时50分21秒",
                isAlerting: false,
                showReminderText: true,
                showMenuBarCountdown: true,
                reminderText: "该打卡了"
            ) == "06时50分21秒",
            "非提醒期间应显示倒计时"
        )
        try expect(
            ReminderLogic.menuBarDisplayTitle(
                countdown: "06时50分21秒",
                isAlerting: false,
                showReminderText: false,
                showMenuBarCountdown: false,
                reminderText: "该打卡了"
            ) == "",
            "关闭倒计时后状态栏不应显示文字"
        )
        try expect(
            ReminderLogic.menuBarDisplayTitle(
                countdown: "06时50分21秒",
                isAlerting: true,
                showReminderText: true,
                showMenuBarCountdown: false,
                reminderText: "该打卡了"
            ) == "该打卡了",
            "关闭倒计时后提醒期间仍应显示自定义文字"
        )

        try expect(
            ReminderLogic.enhancedAlertBody(
                ruleName: "上班",
                deadline: date(year: 2026, month: 8, day: 12, hour: 9, minute: 0),
                graceEnd: date(year: 2026, month: 8, day: 12, hour: 9, minute: 10),
                now: date(year: 2026, month: 8, day: 12, hour: 8, minute: 40)
            ) == "还有 20 分钟，请记得打上班卡",
            "上班提醒应使用上班文案"
        )
        try expect(
            ReminderLogic.enhancedAlertBody(
                ruleName: "中午下班",
                deadline: date(year: 2026, month: 8, day: 12, hour: 12, minute: 0),
                graceEnd: date(year: 2026, month: 8, day: 12, hour: 12, minute: 10),
                now: date(year: 2026, month: 8, day: 12, hour: 11, minute: 55)
            ) == "还有 5 分钟，请记得打下班卡",
            "下班提醒应使用下班文案"
        )
        try expect(
            ReminderLogic.punchKindLabel(ruleName: "下午上班") == "上班",
            "下午上班应归为上班类型"
        )

        _ = lateRule
        print("logic tests passed")
    }
}
