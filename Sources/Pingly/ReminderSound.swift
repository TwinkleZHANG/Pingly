import AppKit

@MainActor
enum ReminderSoundPlayer {
    static func playIfEnabled() {
        let store = AppStore.shared
        guard store.soundEnabled else { return }
        play(store.reminderSound)
    }

    static func play(_ choice: ReminderSoundChoice) {
        NSSound(named: NSSound.Name(choice.rawValue))?.play()
    }
}
