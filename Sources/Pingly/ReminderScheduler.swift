import AppKit
import Foundation

@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private var timer: Timer?
    private var intervalAnchors: [UUID: Date] = [:]
    private var intervalWasActive: [UUID: Bool] = [:]
    private var lastScheduledOccurrences: [UUID: Date] = [:]
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let now = Date()
        for reminder in AppStore.shared.reminders where reminder.kind == .interval {
            intervalAnchors[reminder.id] = now
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                ReminderScheduler.shared.tick()
            }
        }
        timer?.tolerance = 0.15

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        tick()
    }

    private func tick() {
        let store = AppStore.shared
        let now = Date()
        let currentIDs = Set(store.reminders.map(\.id))
        intervalAnchors = intervalAnchors.filter { currentIDs.contains($0.key) }
        intervalWasActive = intervalWasActive.filter { currentIDs.contains($0.key) }
        lastScheduledOccurrences = lastScheduledOccurrences.filter { currentIDs.contains($0.key) }

        if store.isPaused {
            for reminder in store.reminders where reminder.kind == .interval {
                intervalAnchors[reminder.id] = now
            }
            return
        }

        // 定时提醒优先占用角色，但不再阻塞纯文字间隔提醒。
        if let dueScheduled = dueScheduledReminder(at: now, in: store.reminders) {
            ReminderOverlayCoordinator.shared.enqueueScheduled(
                dueScheduled,
                character: store.characterForNextAppearance
            )
        }

        for reminder in store.reminders where reminder.kind == .interval && reminder.isEnabled {
            let isActive = intervalRuleIsActive(reminder, at: now)
            let wasActive = intervalWasActive[reminder.id] ?? false
            intervalWasActive[reminder.id] = isActive

            guard isActive else {
                intervalAnchors[reminder.id] = now
                continue
            }

            if !wasActive || intervalAnchors[reminder.id] == nil {
                intervalAnchors[reminder.id] = now
                continue
            }

            let seconds = TimeInterval(max(1, reminder.intervalMinutes ?? 5) * 60)
            guard let anchor = intervalAnchors[reminder.id], now.timeIntervalSince(anchor) >= seconds else {
                continue
            }

            let didShow = ReminderOverlayCoordinator.shared.showInterval(
                reminder,
                character: store.characterForNextAppearance
            )
            if didShow {
                intervalAnchors[reminder.id] = now
            }
        }
    }

    private func dueScheduledReminder(at now: Date, in reminders: [ReminderItem]) -> ReminderItem? {
        for reminder in reminders where reminder.kind == .scheduled && reminder.isEnabled {
            if ReminderOverlayCoordinator.shared.hasPendingScheduled(reminderID: reminder.id) {
                continue
            }
            guard let occurrence = mostRecentOccurrence(of: reminder, at: now) else { continue }
            let age = now.timeIntervalSince(occurrence)

            if reminder.repeatRule == .none && age > 5 {
                if let index = AppStore.shared.reminders.firstIndex(where: { $0.id == reminder.id }) {
                    AppStore.shared.reminders[index].isEnabled = false
                }
                continue
            }

            guard age >= 0, age <= 5 else { continue }
            if let last = lastScheduledOccurrences[reminder.id],
               abs(last.timeIntervalSince(occurrence)) < 0.5 {
                continue
            }

            lastScheduledOccurrences[reminder.id] = occurrence
            return reminder
        }
        return nil
    }

    private func intervalRuleIsActive(_ reminder: ReminderItem, at date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: date)

        switch reminder.activeDateScope {
        case .always:
            break
        case .today:
            guard let selectedDay = reminder.activeStartDate,
                  calendar.isDate(selectedDay, inSameDayAs: date) else { return false }
        case .dateRange:
            guard let start = reminder.activeStartDate,
                  let end = reminder.activeEndDate else { return false }
            let startDay = calendar.startOfDay(for: start)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            guard date >= startDay, date < endExclusive else { return false }
        }

        guard reminder.usesActiveHours,
              let startTime = reminder.activeStartTime,
              let endTime = reminder.activeEndTime else { return true }

        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        let start = calendar.date(
            bySettingHour: startComponents.hour ?? 0,
            minute: startComponents.minute ?? 0,
            second: 0,
            of: startOfToday
        ) ?? startOfToday
        let end = calendar.date(
            bySettingHour: endComponents.hour ?? 23,
            minute: endComponents.minute ?? 59,
            second: 59,
            of: startOfToday
        ) ?? startOfToday

        if end >= start { return date >= start && date <= end }
        return date >= start || date <= end
    }

    private func mostRecentOccurrence(of reminder: ReminderItem, at now: Date) -> Date? {
        guard let anchor = reminder.scheduledDate else { return nil }
        let calendar = Calendar.current
        if reminder.repeatRule == .none { return anchor }
        guard now >= anchor else { return nil }

        let anchorComponents = calendar.dateComponents([.month, .day, .weekday, .hour, .minute, .second], from: anchor)
        var matching = DateComponents()
        matching.hour = anchorComponents.hour
        matching.minute = anchorComponents.minute
        matching.second = anchorComponents.second

        switch reminder.repeatRule {
        case .none:
            return anchor
        case .daily:
            break
        case .weekly:
            matching.weekday = anchorComponents.weekday
        case .monthly:
            matching.day = anchorComponents.day
        case .yearly:
            matching.month = anchorComponents.month
            matching.day = anchorComponents.day
        }

        let searchStart = now.addingTimeInterval(1)
        guard let occurrence = calendar.nextDate(
            after: searchStart,
            matching: matching,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward
        ), occurrence >= anchor else { return nil }
        return occurrence
    }

    @objc private func didWake() {
        let now = Date()
        let store = AppStore.shared
        guard !store.isPaused else { return }

        // 默认：唤醒后立即显示一次符合规则的间隔提醒，再重新计时。
        if let reminder = store.reminders.first(where: {
            $0.kind == .interval && $0.isEnabled && intervalRuleIsActive($0, at: now)
        }) {
            intervalAnchors[reminder.id] = now
            _ = ReminderOverlayCoordinator.shared.showInterval(
                reminder,
                character: store.characterForNextAppearance
            )
        }
    }
}
