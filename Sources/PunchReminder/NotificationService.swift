import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    static let categoryId = "PUNCH_REMIND"
    static let confirmActionId = "PUNCH_CONFIRM"
    static let snoozeActionId = "PUNCH_SNOOZE"
    static let ruleIdKey = "ruleId"

    var onConfirm: ((UUID) -> Void)?
    var onSnooze: ((UUID) -> Void)?

    func configure() {
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionId,
            title: "稍后",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [snooze],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([category])
        center.delegate = self
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion?(granted)
        }
    }

    func authorizationStatus(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
    }

    func send(occurrence: ReminderLogic.Occurrence, soundEnabled: Bool, tone: AlertTone) {
        let content = UNMutableNotificationContent()
        content.title = "\(occurrence.rule.name)打卡"
        content.body = Self.alertBody(for: occurrence)
        content.categoryIdentifier = Self.categoryId
        content.userInfo = [Self.ruleIdKey: occurrence.rule.id.uuidString]
        content.sound = soundEnabled ? ReminderSound.notificationSound(tone) : nil
        enqueue(
            content,
            identifier: "\(occurrence.rule.id.uuidString)-\(Int(Date().timeIntervalSince1970))"
        )
    }

    static func alertBody(for occurrence: ReminderLogic.Occurrence, now: Date = Date()) -> String {
        ReminderLogic.enhancedAlertBody(
            ruleName: occurrence.rule.name,
            deadline: occurrence.deadline,
            graceEnd: occurrence.graceEnd,
            now: now
        )
    }

    func sendPreview(soundEnabled: Bool, tone: AlertTone, completion: @escaping (String?) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let warning = Self.bannerWarning(from: settings)
            if settings.authorizationStatus == .denied {
                DispatchQueue.main.async { completion(warning) }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "上班打卡"
            content.body = "还有 20 分钟，请记得打卡"
            content.categoryIdentifier = Self.categoryId
            content.sound = soundEnabled ? ReminderSound.notificationSound(tone) : nil
            self.enqueue(
                content,
                identifier: "punch-preview-\(Int(Date().timeIntervalSince1970))"
            ) { error in
                DispatchQueue.main.async {
                    if let error {
                        completion("无法发送通知：\(error.localizedDescription)")
                    } else {
                        completion(warning)
                    }
                }
            }
        }
    }

    private func enqueue(
        _ content: UNMutableNotificationContent,
        identifier: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
    }

    static func bannerWarning(from settings: UNNotificationSettings) -> String? {
        switch settings.authorizationStatus {
        case .denied, .notDetermined:
            return "未获得通知权限，请在「系统设置 › 通知」中允许「朝夕打卡」。"
        case .provisional:
            return "当前是安静通知，横幅会被隐藏。请在「系统设置 › 通知 › 朝夕打卡」中改为横幅。"
        default:
            break
        }
        if settings.alertSetting == .disabled {
            return "系统关闭了横幅。请在「系统设置 › 通知 › 朝夕打卡」中打开允许通知并选择横幅。"
        }
        return nil
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        guard let raw = info[Self.ruleIdKey] as? String, let ruleId = UUID(uuidString: raw) else {
            completionHandler()
            return
        }
        switch response.actionIdentifier {
        case Self.confirmActionId:
            DispatchQueue.main.async { self.onConfirm?(ruleId) }
        case Self.snoozeActionId:
            DispatchQueue.main.async { self.onSnooze?(ruleId) }
        default:
            break
        }
        completionHandler()
    }
}
