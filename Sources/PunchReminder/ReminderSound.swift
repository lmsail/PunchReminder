import AppKit
import UserNotifications

enum ReminderSound {
    private static var current: NSSound?

    static func notificationSound(_ tone: AlertTone) -> UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(tone.fileName))
    }

    static func play(_ tone: AlertTone) {
        current?.stop()
        let sound = NSSound(named: NSSound.Name(tone.systemName))
        sound?.volume = 1
        current = sound
        if let sound {
            sound.play()
            return
        }
        NSSound.beep()
    }
}
