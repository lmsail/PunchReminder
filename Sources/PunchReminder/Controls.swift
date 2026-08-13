import SwiftUI
import AppKit

extension View {
    func appChrome(_ store: AppStore) -> some View {
        dynamicTypeSize(store.fontSize.dynamicTypeSize)
            .environment(\.font, .system(size: 13 * store.fontSize.scale))
    }
}

extension AppFontSize {
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .xSmall
        case .standard: return .medium
        case .large: return .xLarge
        case .extraLarge: return .xxxLarge
        }
    }
}

enum Surface {
    static var window: Color { Color(nsColor: .windowBackgroundColor) }
    static var card: Color { Color(nsColor: .textBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var label: Color { Color(nsColor: .labelColor) }
    static var secondary: Color { Color(nsColor: .secondaryLabelColor) }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Surface.separator.opacity(0.7), lineWidth: 1)
            )
    }
}

struct StatusChip: View {
    var text: String
    var tone: Tone

    enum Tone {
        case success, danger, warning, neutral
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(foreground.opacity(0.14), in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .success: return .green
        case .danger: return .red
        case .warning: return .orange
        case .neutral: return Surface.secondary
        }
    }
}

struct ClockTimePicker: View {
    @Binding var date: Date

    var body: some View {
        HStack(spacing: 10) {
            Picker("时", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(minWidth: 72)
            Text("时")
                .foregroundStyle(Surface.secondary)
            Picker("分", selection: minuteBinding) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(minWidth: 72)
            Text("分")
                .foregroundStyle(Surface.secondary)
        }
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: date) },
            set: { update(hour: $0, minute: Calendar.current.component(.minute, from: date)) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: date) },
            set: { update(hour: Calendar.current.component(.hour, from: date), minute: $0) }
        )
    }

    private func update(hour: Int, minute: Int) {
        date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
}

struct MonthCalendar: View {
    @Binding var date: Date

    private let calendar = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                Spacer()
                Text(monthTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Surface.label)
                Spacer()
                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Surface.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }
        }
        .padding(16)
        .background(Surface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Surface.separator.opacity(0.7), lineWidth: 1)
        )
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private var days: [Date?] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let firstWeekday = calendar.component(.weekday, from: start)
        let leading = firstWeekday - 1
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        var items: [Date?] = Array(repeating: nil, count: leading)
        for day in 1...count {
            items.append(calendar.date(byAdding: .day, value: day - 1, to: start))
        }
        while items.count % 7 != 0 {
            items.append(nil)
        }
        return items
    }

    private func dayCell(_ day: Date?) -> some View {
        Group {
            if let day {
                let selected = calendar.isDate(day, inSameDayAs: date)
                let today = calendar.isDateInToday(day)
                Button {
                    date = calendar.date(
                        bySettingHour: calendar.component(.hour, from: date),
                        minute: calendar.component(.minute, from: date),
                        second: 0,
                        of: day
                    ) ?? day
                } label: {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.title3.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Surface.label)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            Circle().fill(selected ? Color.accentColor : Color.clear)
                        )
                        .overlay {
                            if today && !selected {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(minHeight: 40)
            }
        }
    }

    private func shiftMonth(_ value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: date) {
            date = next
        }
    }
}

struct ConfirmPunchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var picked = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let request = store.pendingConfirm {
                VStack(alignment: .leading, spacing: 6) {
                    Text("确认打卡时间")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Surface.label)
                    Text(request.subtitle)
                        .font(.callout)
                        .foregroundStyle(Surface.secondary)
                }

                Button(request.shortcutTitle) {
                    store.completePendingConfirm(at: clamped(request.defaultDate, request: request))
                    dismissWindow(id: "confirm-punch")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Text("或手动选择时间")
                    .font(.caption)
                    .foregroundStyle(Surface.secondary)

                ClockTimePicker(date: $picked)
                    .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    Button("取消") {
                        store.cancelPendingConfirm()
                        dismissWindow(id: "confirm-punch")
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("确定") {
                        store.completePendingConfirm(at: clamped(picked, request: request))
                        dismissWindow(id: "confirm-punch")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("没有待确认的打卡")
                    .foregroundStyle(Surface.secondary)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Surface.window)
        .onAppear {
            if let request = store.pendingConfirm {
                picked = min(max(request.pickerDate, request.day), request.latest)
            }
        }
        .onChange(of: store.pendingConfirm) { _, request in
            if let request {
                picked = min(max(request.pickerDate, request.day), request.latest)
            }
        }
    }

    private func clamped(_ date: Date, request: ConfirmPunchRequest) -> Date {
        min(max(date, request.day), request.latest)
    }
}
