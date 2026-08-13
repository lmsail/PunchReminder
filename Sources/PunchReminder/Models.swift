import Foundation
import AppKit

struct PunchRule: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var hour: Int
    var minute: Int
    var weekdays: [Int]
    var leadMinutes: Int
    var intervalMinutes: Int
    var graceMinutes: Int
    var enabled: Bool
    var sortIndex: Int = 0

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var timeMinutes: Int {
        hour * 60 + minute
    }

    static func makeDefaultRules() -> [PunchRule] {
        [
            PunchRule(
                id: UUID(),
                name: "上班",
                hour: 9,
                minute: 0,
                weekdays: [2, 3, 4, 5, 6],
                leadMinutes: 20,
                intervalMinutes: 2,
                graceMinutes: 10,
                enabled: true,
                sortIndex: 0
            ),
            PunchRule(
                id: UUID(),
                name: "下班",
                hour: 18,
                minute: 0,
                weekdays: [2, 3, 6],
                leadMinutes: 20,
                intervalMinutes: 2,
                graceMinutes: 10,
                enabled: true,
                sortIndex: 1
            ),
            PunchRule(
                id: UUID(),
                name: "晚下班",
                hour: 21,
                minute: 0,
                weekdays: [4, 5],
                leadMinutes: 20,
                intervalMinutes: 2,
                graceMinutes: 10,
                enabled: true,
                sortIndex: 2
            ),
        ]
    }

    /// 旧数据缺 sortIndex 或序号重复时按时间正序；否则按手动拖拽顺序。
    static func normalizedOrder(_ rules: [PunchRule]) -> [PunchRule] {
        var result = rules
        let needsTimeSort = result.contains { $0.sortIndex < 0 }
            || Set(result.map(\.sortIndex)).count != result.count
        if needsTimeSort {
            result.sort { lhs, rhs in
                if lhs.timeMinutes != rhs.timeMinutes {
                    return lhs.timeMinutes < rhs.timeMinutes
                }
                return lhs.name < rhs.name
            }
        } else {
            result.sort { $0.sortIndex < $1.sortIndex }
        }
        for index in result.indices {
            result[index].sortIndex = index
        }
        return result
    }
}

extension PunchRule {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        weekdays = try container.decode([Int].self, forKey: .weekdays)
        leadMinutes = try container.decode(Int.self, forKey: .leadMinutes)
        intervalMinutes = try container.decode(Int.self, forKey: .intervalMinutes)
        graceMinutes = try container.decodeIfPresent(Int.self, forKey: .graceMinutes) ?? 10
        enabled = try container.decode(Bool.self, forKey: .enabled)
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? -1
    }
}

struct ConfirmPunchRequest: Identifiable, Equatable {
    var id = UUID()
    var ruleId: UUID
    var historyId: UUID?
    var title: String
    var subtitle: String
    var day: Date
    var defaultDate: Date
    var pickerDate: Date
    var latest: Date
    var shortcutTitle: String
}

struct EnhancedAlert: Equatable {
    var ruleName: String
    var title: String
    var body: String
    var ruleId: UUID?
}

enum OverrideKind: String, Codable {
    case skipDay
    case skipRule
    case replaceTime
}

struct DayOverride: Identifiable, Codable, Equatable {
    var id: UUID
    var day: String
    var kind: OverrideKind
    var ruleId: UUID?
    var hour: Int?
    var minute: Int?

    var timeText: String? {
        guard let hour, let minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var day: String
    var ruleId: UUID
    var ruleName: String
    var deadlineHour: Int
    var deadlineMinute: Int
    var confirmedAt: Date?
    var missed: Bool

    var deadlineText: String {
        String(format: "%02d:%02d", deadlineHour, deadlineMinute)
    }
}

struct DayRuntime: Codable, Equatable {
    var day: String
    var confirmedRuleIds: [UUID]
    var paused: Bool
    var lastFiredAt: [String: Date]
    var snoozeUntil: [String: Date]

    static func empty(day: String) -> DayRuntime {
        DayRuntime(
            day: day,
            confirmedRuleIds: [],
            paused: false,
            lastFiredAt: [:],
            snoozeUntil: [:]
        )
    }
}

struct PersistedState: Codable {
    var rules: [PunchRule]
    var soundEnabled: Bool
    var overrides: [DayOverride]
    var history: [HistoryEntry]
    var dayRuntime: DayRuntime?
    var appearance: AppearanceMode
    var fontSize: AppFontSize
    var alertTone: AlertTone
    var enhancedAlertEnabled: Bool
    var showReminderText: Bool
    var showMenuBarCountdown: Bool
    var reminderText: String

    init(
        rules: [PunchRule],
        soundEnabled: Bool,
        overrides: [DayOverride],
        history: [HistoryEntry],
        dayRuntime: DayRuntime?,
        appearance: AppearanceMode = .system,
        fontSize: AppFontSize = .standard,
        alertTone: AlertTone = .hero,
        enhancedAlertEnabled: Bool = true,
        showReminderText: Bool = true,
        showMenuBarCountdown: Bool = true,
        reminderText: String = "该打卡了"
    ) {
        self.rules = rules
        self.soundEnabled = soundEnabled
        self.overrides = overrides
        self.history = history
        self.dayRuntime = dayRuntime
        self.appearance = appearance
        self.fontSize = fontSize
        self.alertTone = alertTone
        self.enhancedAlertEnabled = enhancedAlertEnabled
        self.showReminderText = showReminderText
        self.showMenuBarCountdown = showMenuBarCountdown
        self.reminderText = reminderText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decode([PunchRule].self, forKey: .rules)
        soundEnabled = try container.decode(Bool.self, forKey: .soundEnabled)
        overrides = try container.decode([DayOverride].self, forKey: .overrides)
        history = try container.decode([HistoryEntry].self, forKey: .history)
        dayRuntime = try container.decodeIfPresent(DayRuntime.self, forKey: .dayRuntime)
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        fontSize = try container.decodeIfPresent(AppFontSize.self, forKey: .fontSize) ?? .standard
        alertTone = try container.decodeIfPresent(AlertTone.self, forKey: .alertTone) ?? .hero
        enhancedAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .enhancedAlertEnabled) ?? true
        showReminderText = try container.decodeIfPresent(Bool.self, forKey: .showReminderText) ?? true
        showMenuBarCountdown = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarCountdown) ?? true
        reminderText = try container.decodeIfPresent(String.self, forKey: .reminderText) ?? "该打卡了"
    }
}

enum AlertTone: String, Codable, CaseIterable, Identifiable {
    case glass
    case hero
    case ping
    case submarine
    case tink
    case pop
    case purr
    case sosumi
    case funk

    var id: String { rawValue }

    var systemName: String {
        switch self {
        case .glass: return "Glass"
        case .hero: return "Hero"
        case .ping: return "Ping"
        case .submarine: return "Submarine"
        case .tink: return "Tink"
        case .pop: return "Pop"
        case .purr: return "Purr"
        case .sosumi: return "Sosumi"
        case .funk: return "Funk"
        }
    }

    var fileName: String { "\(systemName).aiff" }

    var title: String {
        switch self {
        case .glass: return "清脆"
        case .hero: return "号角"
        case .ping: return "提示"
        case .submarine: return "低音"
        case .tink: return "铃铛"
        case .pop: return "气泡"
        case .purr: return "轻柔"
        case .sosumi: return "经典"
        case .funk: return "节拍"
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum AppFontSize: String, Codable, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "较小"
        case .standard: return "标准"
        case .large: return "较大"
        case .extraLarge: return "最大"
        }
    }

    var scale: Double {
        switch self {
        case .small: return 0.88
        case .standard: return 1.0
        case .large: return 1.2
        case .extraLarge: return 1.4
        }
    }

    var menuBarPointSize: Double {
        switch self {
        case .small: return 11
        case .standard: return 13
        case .large: return 15
        case .extraLarge: return 17
        }
    }
}

enum WeekdayFormat {
    static let ordered: [(id: Int, label: String)] = [
        (2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日"),
    ]

    static func label(for calendarWeekday: Int) -> String {
        ordered.first { $0.id == calendarWeekday }?.label ?? "\(calendarWeekday)"
    }

    static func joined(_ weekdays: [Int]) -> String {
        ordered.filter { weekdays.contains($0.id) }.map(\.label).joined(separator: "、")
    }
}
