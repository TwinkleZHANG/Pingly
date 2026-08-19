import AppKit
import SwiftUI

@MainActor
final class ReminderOverlayCoordinator: NSObject, NSWindowDelegate {
    static let shared = ReminderOverlayCoordinator()

    private let movingStore = MovingOverlayStore()
    private var movingPanel: NSPanel?
    private var removalWorkItems: [UUID: DispatchWorkItem] = [:]

    private var scheduledQueue: [ReminderItem] = []
    private var deferredIntervals: [ReminderItem] = []
    private var activeWaitingReminders: [ReminderItem] = []
    private var waitingPanel: NSPanel?
    private var waitingTravelWorkItem: DispatchWorkItem?
    private var waitingAttentionWorkItem: DispatchWorkItem?
    private var waitingRotationTimer: Timer?
    private var waitingRotationIndex = 0
    private var snoozeWorkItems: [UUID: DispatchWorkItem] = [:]
    private var waitingAnimation: CharacterAnimation?
    private var waitingCharacter: CharacterProfile?
    private var waitingViewStore: WaitingOverlayStore?
    private var displayedWaitingReminder: ReminderItem?
    private var waitingTargetScreen: NSScreen?
    private var activeWaitingIsPreview = false
    private var rememberedWaitingCenters: [UUID: CGPoint] = [:]
    private var waitingPanelIsExpanded = false
    private var waitingRestingTopLeft: CGPoint?

    private let maximumTextOnlyIntervals = 3

    private var activeWaitingReminder: ReminderItem? {
        get { activeWaitingReminders.first }
        set { activeWaitingReminders = newValue.map { [$0] } ?? [] }
    }

    var isShowing: Bool {
        movingPanel?.isVisible == true || waitingPanel?.isVisible == true || activeWaitingReminder != nil
    }

    func applyWindowPreferences() {
        [movingPanel, waitingPanel].compactMap { $0 }.forEach(applyWindowPreferences(to:))
        let height = AppStore.shared.characterDisplayHeight(for: currentMovingScreen())
        movingStore.items = movingStore.items.map { item in
            var updated = item
            updated.characterHeight = height
            return updated
        }
        waitingViewStore?.characterHeight = AppStore.shared.characterDisplayHeight(
            for: waitingPanel?.screen ?? waitingTargetScreen
        )
        movingStore.objectWillChange.send()
        waitingViewStore?.objectWillChange.send()
        if waitingPanel != nil { resizeWaitingPanelForCurrentState() }
    }

    func hasPendingScheduled(reminderID: UUID) -> Bool {
        activeWaitingReminders.contains(where: { $0.id == reminderID }) ||
            scheduledQueue.contains(where: { $0.id == reminderID }) ||
            snoozeWorkItems[reminderID] != nil
    }

    @discardableResult
    func showPreview(reminder: ReminderItem, character: CharacterProfile?) -> Bool {
        guard let screen = screenUnderMouse() else { return false }
        if reminder.kind == .scheduled && reminder.scheduledDisplayBehavior == .waitForAction {
            guard activeWaitingReminder == nil else { return false }
            activeWaitingReminder = reminder
            activeWaitingIsPreview = true
            demoteMovingCharacterToText()
            beginWaitingTravel(
                reminder: reminder,
                character: character,
                screen: screen
            )
            return true
        }
        return addMovingPresentation(
            reminder: reminder,
            character: character,
            screen: screen,
            role: .preview,
            completion: nil
        )
    }

    @discardableResult
    func showInterval(_ reminder: ReminderItem, character: CharacterProfile?) -> Bool {
        guard let screen = screenUnderMouse() else { return false }
        guard activeIntervalCount < maximumTextOnlyIntervals else { return false }
        let hasUsableCharacter = CharacterAnimationLoader.movementAnimation(
            for: character,
            movesRight: true
        ) != nil
        let mayUseCharacter = !isCharacterOccupied && hasUsableCharacter
        if !mayUseCharacter && activeTextOnlyIntervalCount >= maximumTextOnlyIntervals {
            return false
        }

        return addMovingPresentation(
            reminder: reminder,
            character: mayUseCharacter ? character : nil,
            screen: screen,
            role: .interval,
            completion: nil
        )
    }

    func enqueueScheduled(_ reminder: ReminderItem, character: CharacterProfile?) {
        guard !activeWaitingReminders.contains(where: { $0.id == reminder.id }),
              !scheduledQueue.contains(where: { $0.id == reminder.id }) else { return }

        if !activeWaitingIsPreview,
           activeWaitingReminder != nil,
           waitingPanel != nil || waitingTravelWorkItem != nil {
            activeWaitingReminders.append(reminder)
            waitingViewStore?.reminders = activeWaitingReminders
            refreshWaitingRotation()
            ReminderSoundPlayer.playIfEnabled()
            playWaitingAttentionAnimation()
            return
        }
        scheduledQueue.append(reminder)
        presentNextScheduledIfNeeded(character: character)
    }

    func closeCurrent() {
        removalWorkItems.values.forEach { $0.cancel() }
        removalWorkItems.removeAll()
        waitingTravelWorkItem?.cancel()
        waitingTravelWorkItem = nil
        waitingAttentionWorkItem?.cancel()
        waitingAttentionWorkItem = nil
        waitingRotationTimer?.invalidate()
        waitingRotationTimer = nil
        movingStore.items.removeAll()
        movingPanel?.orderOut(nil)
        movingPanel = nil
        waitingPanel?.orderOut(nil)
        waitingPanel = nil
        activeWaitingReminder = nil
        waitingAnimation = nil
        waitingCharacter = nil
        waitingViewStore = nil
        displayedWaitingReminder = nil
        waitingTargetScreen = nil
        activeWaitingIsPreview = false
        deferredIntervals.removeAll()
    }

    private var activeTextOnlyIntervalCount: Int {
        movingStore.items.filter { $0.role == .interval && $0.animation == nil }.count
    }

    private var activeIntervalCount: Int {
        movingStore.items.filter { $0.role == .interval }.count
    }

    private var isCharacterOccupied: Bool {
        waitingAnimation != nil || movingStore.items.contains(where: { $0.animation != nil })
    }

    private func addMovingPresentation(
        reminder: ReminderItem,
        character: CharacterProfile?,
        screen: NSScreen,
        role: MovingPresentationRole,
        completion: (() -> Void)?
    ) -> Bool {
        if role == .interval,
           movingStore.items.contains(where: { $0.role == .interval && $0.reminder.id == reminder.id }) {
            return false
        }

        // Every active moving item shares one full-screen panel. Keep that
        // panel on its current screen until the batch finishes; relocating it
        // for a newly triggered reminder makes every existing route jump.
        let presentationScreen = currentMovingScreen() ?? screen
        let animationCandidate = CharacterAnimationLoader.movementAnimation(for: character, movesRight: true)
        let willUseCharacter = animationCandidate != nil
        let route = makeRoute(
            for: reminder.routeStyle,
            screenSize: presentationScreen.frame.size,
            textOnly: !willUseCharacter
        )
        let animation = CharacterAnimationLoader.movementAnimation(
            for: character,
            movesRight: route.movesRight
        )
        let duration = reminder.movementSpeed.duration(for: route.distance, textOnly: animation == nil)
        let convoyPosition = fixedConvoyPosition(for: reminder.routeStyle)
        let delay = TimeInterval(convoyPosition) * 2.1
        let item = MovingReminderPresentation(
            reminder: reminder,
            animation: animation,
            characterHeight: AppStore.shared.characterDisplayHeight(for: presentationScreen),
            route: route,
            startDate: Date().addingTimeInterval(delay),
            duration: duration,
            role: role
        )

        movingStore.items.append(item)
        showMovingPanel(on: presentationScreen)
        if role != .preview { ReminderSoundPlayer.playIfEnabled() }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.removeMovingPresentation(id: item.id)
            completion?()
        }
        removalWorkItems[item.id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.2, execute: workItem)
        return true
    }

    private func fixedConvoyPosition(for style: ReminderRouteStyle) -> Int {
        guard style == .centerLeftToRight || style == .centerRightToLeft else { return 0 }
        return movingStore.items.filter { item in
            item.reminder.routeStyle == style && item.role == .interval
        }.count
    }

    private func makeRoute(
        for style: ReminderRouteStyle,
        screenSize: CGSize,
        textOnly: Bool
    ) -> OverlayRoute {
        if style == .centerLeftToRight || style == .centerRightToLeft {
            return OverlayRoute.make(style: style, in: screenSize)
        }

        var candidate = OverlayRoute.make(style: style, in: screenSize)
        guard textOnly else { return candidate }
        for _ in 0..<8 {
            let overlaps = movingStore.items
                .filter { $0.animation == nil }
                .contains { candidate.isNearlyIdentical(to: $0.route) }
            if !overlaps { break }
            candidate = OverlayRoute.make(style: style, in: screenSize)
        }
        return candidate
    }

    private func showMovingPanel(on screen: NSScreen) {
        if let panel = movingPanel {
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlayPanel(panel, frame: screen.frame, ignoresMouse: true)
        let rootView = MovingOverlayView(store: movingStore)
        let hostingView = NSHostingView(
            rootView: rootView.frame(width: screen.frame.width, height: screen.frame.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        movingPanel = panel
    }

    private func currentMovingScreen() -> NSScreen? {
        guard let panel = movingPanel else { return nil }
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(panel.frame).width * lhs.frame.intersection(panel.frame).height
                < rhs.frame.intersection(panel.frame).width * rhs.frame.intersection(panel.frame).height
        }
    }

    private func removeMovingPresentation(id: UUID) {
        removalWorkItems[id]?.cancel()
        removalWorkItems[id] = nil
        movingStore.items.removeAll { $0.id == id }
        if movingStore.items.isEmpty {
            movingPanel?.orderOut(nil)
            movingPanel = nil
        }
        drainDeferredIntervals()
    }

    private func demoteMovingCharacterToText() {
        let characterIntervals = movingStore.items.filter {
            $0.role == .interval && $0.animation != nil
        }.count
        let overflow = max(
            0,
            activeTextOnlyIntervalCount + characterIntervals - maximumTextOnlyIntervals
        )
        if overflow > 0 {
            let candidates = movingStore.items
                .filter { $0.role == .interval && $0.animation == nil }
                .sorted { $0.startDate > $1.startDate }
                .prefix(overflow)
            for candidate in candidates {
                removalWorkItems[candidate.id]?.cancel()
                removalWorkItems[candidate.id] = nil
                movingStore.items.removeAll { $0.id == candidate.id }
                deferredIntervals.append(candidate.reminder)
            }
        }

        movingStore.items = movingStore.items.map { item in
            guard item.animation != nil else { return item }
            var updated = item
            updated.animation = nil
            return updated
        }
    }

    private func drainDeferredIntervals() {
        while !deferredIntervals.isEmpty,
              activeTextOnlyIntervalCount < maximumTextOnlyIntervals {
            let reminder = deferredIntervals.removeFirst()
            if !showInterval(reminder, character: nil) {
                deferredIntervals.insert(reminder, at: 0)
                break
            }
        }
    }

    private func presentNextScheduledIfNeeded(character: CharacterProfile?) {
        guard activeWaitingReminder == nil, !scheduledQueue.isEmpty,
              let screen = screenUnderMouse() else { return }

        let reminder = scheduledQueue.removeFirst()
        activeWaitingReminder = reminder
        demoteMovingCharacterToText()

        if reminder.scheduledDisplayBehavior == .sameAsInterval {
            let didShow = addMovingPresentation(
                reminder: reminder,
                character: character ?? AppStore.shared.characterForNextAppearance,
                screen: screen,
                role: .scheduledPassThrough,
                completion: { [weak self] in
                    Self.finishOneTimeReminderIfNeeded(reminder)
                    self?.activeWaitingReminder = nil
                    self?.presentNextScheduledIfNeeded(
                        character: AppStore.shared.characterForNextAppearance
                    )
                }
            )
            if !didShow {
                activeWaitingReminder = nil
                scheduledQueue.insert(reminder, at: 0)
            }
            return
        }

        beginWaitingTravel(
            reminder: reminder,
            character: character,
            screen: screen
        )
    }

    private func beginWaitingTravel(
        reminder: ReminderItem,
        character: CharacterProfile?,
        screen: NSScreen
    ) {
        let requestedScreen = rememberedWaitingCenters[reminder.id].flatMap { center in
            NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) })
        } ?? screen
        let targetScreen = currentMovingScreen() ?? requestedScreen
        waitingTargetScreen = targetScreen
        let route = OverlayRoute.make(style: reminder.routeStyle, in: targetScreen.frame.size)
        let stopProgress: CGFloat = 0.35
        let defaultStopPoint = route.point(at: stopProgress)
        let rememberedCenter = rememberedWaitingCenters[reminder.id].flatMap { center in
            NSMouseInRect(center, targetScreen.frame, false) ? center : nil
        }
        let stopPoint = rememberedCenter.map { center in
            CGPoint(
                x: center.x - targetScreen.frame.minX,
                y: targetScreen.frame.maxY - center.y
            )
        } ?? defaultStopPoint
        let travelRoute = OverlayRoute(start: route.start, end: stopPoint)
        let characterProfile = character ?? AppStore.shared.characterForNextAppearance
        waitingCharacter = characterProfile
        let travelAnimation = CharacterAnimationLoader.movementAnimation(
            for: characterProfile,
            movesRight: route.movesRight
        )
        waitingAnimation = CharacterAnimationLoader.stationaryAnimation(for: characterProfile)
        let duration = max(
            3,
            reminder.movementSpeed.duration(
                for: route.distance,
                textOnly: travelAnimation == nil
            ) * TimeInterval(stopProgress)
        )
        let travel = MovingReminderPresentation(
            reminder: reminder,
            animation: travelAnimation,
            characterHeight: AppStore.shared.characterDisplayHeight(for: targetScreen),
            route: travelRoute,
            startDate: Date(),
            duration: duration,
            role: .scheduledTravel
        )
        movingStore.items.append(travel)
        showMovingPanel(on: targetScreen)
        if !activeWaitingIsPreview { ReminderSoundPlayer.playIfEnabled() }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.removeMovingPresentation(id: travel.id)
            self.showWaitingPanel(
                reminder: reminder,
                at: stopPoint,
                on: targetScreen,
                movesRight: route.movesRight
            )
        }
        waitingTravelWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func showWaitingPanel(
        reminder: ReminderItem,
        at point: CGPoint,
        on screen: NSScreen,
        movesRight: Bool
    ) {
        waitingPanel?.orderOut(nil)

        let hasCharacter = waitingAnimation != nil
        waitingPanelIsExpanded = false
        let reminders = activeWaitingReminders.isEmpty ? [reminder] : activeWaitingReminders
        displayedWaitingReminder = reminders.first
        let size = waitingPanelSize(
            for: reminders[0],
            hasCharacter: hasCharacter,
            expanded: false
        )
        let desiredOrigin = CGPoint(
            x: screen.frame.minX + point.x - size.width / 2,
            y: screen.frame.maxY - point.y - size.height / 2
        )
        let origin = CGPoint(
            x: min(max(screen.visibleFrame.minX + 12, desiredOrigin.x), screen.visibleFrame.maxX - size.width - 12),
            y: min(max(screen.visibleFrame.minY + 12, desiredOrigin.y), screen.visibleFrame.maxY - size.height - 12)
        )
        let frame = NSRect(origin: origin, size: size)
        waitingRestingTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlayPanel(panel, frame: frame, ignoresMouse: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        let viewStore = WaitingOverlayStore(
            reminders: reminders,
            animation: waitingAnimation,
            movesRight: movesRight,
            characterHeight: AppStore.shared.characterDisplayHeight(for: screen)
        )
        waitingViewStore = viewStore
        let hostingView = NSHostingView(
            rootView: WaitingReminderView(
                store: viewStore,
                onComplete: { [weak self] reminder in self?.completeWaitingReminder(reminder) },
                onSnooze: { [weak self] reminder in self?.snoozeWaitingReminder(reminder) },
                onViewAll: { PinglyWindowCoordinator.shared.showReminders() },
                onExpansionChanged: { [weak self] expanded in
                    self?.resizeWaitingPanel(
                        hasCharacter: hasCharacter,
                        expanded: expanded
                    )
                }
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        waitingPanel = panel
        refreshWaitingRotation()
    }

    private func waitingPanelSize(
        for reminder: ReminderItem,
        hasCharacter: Bool,
        expanded: Bool
    ) -> NSSize {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let textWidth = max(
            24,
            ceil((reminder.title as NSString).size(withAttributes: [.font: font]).width)
        ) + 24
        let textHeight: CGFloat = 33
        let characterSize = waitingViewStore?.characterHeight
            ?? AppStore.shared.characterDisplayHeight(for: waitingTargetScreen)
        let contentSize: NSSize
        if hasCharacter {
            switch reminder.textPosition {
            case .above, .below:
                contentSize = NSSize(
                    width: max(characterSize, textWidth),
                    height: characterSize + textHeight + 3
                )
            case .behind, .ahead:
                contentSize = NSSize(
                    width: characterSize + textWidth + 4,
                    height: max(characterSize, textHeight)
                )
            }
        } else {
            contentSize = NSSize(width: textWidth, height: textHeight)
        }
        let collapsedWidth = contentSize.width + 8
        let collapsedHeight = contentSize.height + 8

        guard expanded else {
            return NSSize(width: collapsedWidth, height: collapsedHeight)
        }
        return NSSize(
            width: max(collapsedWidth, hasCharacter ? 350 : 250),
            height: collapsedHeight + 88
        )
    }

    private func resizeWaitingPanel(
        hasCharacter: Bool,
        expanded: Bool,
        force: Bool = false
    ) {
        guard let panel = waitingPanel,
              force || waitingPanelIsExpanded != expanded else { return }
        let wasExpanded = waitingPanelIsExpanded
        waitingPanelIsExpanded = expanded
        let size = waitingPanelSize(
            for: displayedWaitingReminder ?? activeWaitingReminders.first ?? ReminderItem(
                title: "提醒",
                kind: .scheduled
            ),
            hasCharacter: hasCharacter,
            expanded: expanded
        )
        // Keep the reminder header's top-left corner fixed. The action row grows
        // downward, so hover enter/exit never changes the reminder's resting spot.
        if expanded && !wasExpanded {
            waitingRestingTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        }
        let topLeft = waitingRestingTopLeft
            ?? CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        var frame = NSRect(
            x: topLeft.x,
            y: topLeft.y - size.height,
            width: size.width,
            height: size.height
        )
        frame.origin = clampedOrigin(for: frame, preferredScreen: panel.screen)
        // Avoid forcing an immediate synchronous redraw of the overlay. The
        // hosting view will redraw on the next display pass without pausing the
        // independently moving interval panel.
        panel.setFrame(frame, display: false, animate: false)
    }

    private func resizeWaitingPanelForCurrentState() {
        guard waitingPanel != nil else { return }
        resizeWaitingPanel(
            hasCharacter: waitingAnimation != nil,
            expanded: waitingPanelIsExpanded,
            force: true
        )
    }

    private func refreshWaitingRotation() {
        waitingRotationTimer?.invalidate()
        waitingRotationTimer = nil
        guard !activeWaitingReminders.isEmpty else { return }

        if let displayedWaitingReminder,
           let index = activeWaitingReminders.firstIndex(where: { $0.id == displayedWaitingReminder.id }) {
            waitingRotationIndex = index
            waitingViewStore?.displayedReminder = displayedWaitingReminder
        } else {
            waitingRotationIndex = 0
            displayWaitingReminder(activeWaitingReminders[0])
        }

        guard activeWaitingReminders.count > 1 else { return }
        waitingRotationTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.activeWaitingReminders.isEmpty else { return }
                self.waitingRotationIndex = (self.waitingRotationIndex + 1) % self.activeWaitingReminders.count
                self.displayWaitingReminder(self.activeWaitingReminders[self.waitingRotationIndex])
            }
        }
        waitingRotationTimer?.tolerance = 0.1
    }

    private func displayWaitingReminder(_ reminder: ReminderItem) {
        displayedWaitingReminder = reminder
        waitingViewStore?.displayedReminder = reminder
        resizeWaitingPanelForCurrentState()
    }

    private func playWaitingAttentionAnimation() {
        guard let waitingViewStore else { return }
        waitingAttentionWorkItem?.cancel()
        if let attention = CharacterAnimationLoader.attentionAnimation(for: waitingCharacter) {
            waitingViewStore.animation = attention
        }
        let workItem = DispatchWorkItem { [weak self, weak waitingViewStore] in
            guard let self else { return }
            waitingViewStore?.animation = self.waitingAnimation
            self.waitingAttentionWorkItem = nil
        }
        waitingAttentionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: workItem)
    }

    private func completeWaitingReminder(_ reminder: ReminderItem) {
        guard activeWaitingReminders.contains(where: { $0.id == reminder.id }) else { return }
        rememberedWaitingCenters[reminder.id] = nil
        if !activeWaitingIsPreview {
            Self.finishOneTimeReminderIfNeeded(reminder)
        }
        removeWaitingReminder(reminder)
    }

    private func snoozeWaitingReminder(_ reminder: ReminderItem) {
        guard activeWaitingReminders.contains(where: { $0.id == reminder.id }) else { return }
        if activeWaitingIsPreview {
            rememberedWaitingCenters[reminder.id] = nil
            finishCurrentWaitingPresentation()
            return
        }
        if let panel = waitingPanel {
            let collapsedSize = waitingPanelSize(
                for: reminder,
                hasCharacter: waitingAnimation != nil,
                expanded: false
            )
            let topLeft = waitingRestingTopLeft
                ?? CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
            rememberedWaitingCenters[reminder.id] = CGPoint(
                x: topLeft.x + collapsedSize.width / 2,
                y: topLeft.y - collapsedSize.height / 2
            )
        }
        removeWaitingReminder(reminder)

        snoozeWorkItems[reminder.id]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.snoozeWorkItems[reminder.id] = nil
            self.enqueueScheduled(
                reminder,
                character: AppStore.shared.characterForNextAppearance
            )
        }
        snoozeWorkItems[reminder.id] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TimeInterval(max(1, reminder.snoozeMinutes) * 60),
            execute: workItem
        )
    }

    private func removeWaitingReminder(_ reminder: ReminderItem) {
        activeWaitingReminders.removeAll { $0.id == reminder.id }
        guard !activeWaitingReminders.isEmpty else {
            finishCurrentWaitingPresentation()
            return
        }
        waitingViewStore?.reminders = activeWaitingReminders
        refreshWaitingRotation()
    }

    private func finishCurrentWaitingPresentation() {
        waitingTravelWorkItem?.cancel()
        waitingTravelWorkItem = nil
        waitingAttentionWorkItem?.cancel()
        waitingAttentionWorkItem = nil
        waitingRotationTimer?.invalidate()
        waitingRotationTimer = nil
        waitingRotationIndex = 0
        waitingPanel?.orderOut(nil)
        waitingPanel = nil
        waitingPanelIsExpanded = false
        waitingRestingTopLeft = nil
        activeWaitingReminder = nil
        waitingAnimation = nil
        waitingCharacter = nil
        waitingViewStore = nil
        displayedWaitingReminder = nil
        waitingTargetScreen = nil
        activeWaitingIsPreview = false
        presentNextScheduledIfNeeded(character: AppStore.shared.characterForNextAppearance)
    }

    private static func finishOneTimeReminderIfNeeded(_ reminder: ReminderItem) {
        guard reminder.repeatRule == .none,
              let index = AppStore.shared.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        AppStore.shared.reminders[index].isEnabled = false
    }

    private func configureOverlayPanel(_ panel: NSPanel, frame: NSRect, ignoresMouse: Bool) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = ignoresMouse
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        applyWindowPreferences(to: panel)
        panel.isReleasedWhenClosed = false
        panel.setFrame(frame, display: false)
    }

    private func applyWindowPreferences(to panel: NSPanel) {
        let store = AppStore.shared
        panel.sharingType = store.hideDuringScreenShare ? .none : .readOnly
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .transient]
        if store.showInFullScreen { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, panel === waitingPanel else { return }
        // Resizing the panel for hover or rotating reminder text also emits
        // windowDidMove. Only a held primary mouse button identifies an actual
        // user drag; treating programmatic moves as drags creates an
        // expand-collapse loop and cursor flicker.
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return }
        let origin = clampedOrigin(for: panel.frame, preferredScreen: panel.screen)
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
        waitingRestingTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        if waitingPanelIsExpanded {
            waitingViewStore?.collapseGeneration += 1
        }
    }

    private func clampedOrigin(for frame: NSRect, preferredScreen: NSScreen?) -> CGPoint {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) })
            ?? preferredScreen
            ?? screenUnderMouse()
        guard let visibleFrame = screen?.visibleFrame else { return frame.origin }
        let margin: CGFloat = 12
        return CGPoint(
            x: min(max(visibleFrame.minX + margin, frame.minX), visibleFrame.maxX - frame.width - margin),
            y: min(max(visibleFrame.minY + margin, frame.minY), visibleFrame.maxY - frame.height - margin)
        )
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }
}

private enum MovingPresentationRole {
    case interval
    case scheduledPassThrough
    case scheduledTravel
    case preview
}

private struct MovingReminderPresentation: Identifiable {
    let id = UUID()
    let reminder: ReminderItem
    var animation: CharacterAnimation?
    var characterHeight: CGFloat
    let route: OverlayRoute
    let startDate: Date
    let duration: TimeInterval
    let role: MovingPresentationRole
}

@MainActor
private final class MovingOverlayStore: ObservableObject {
    @Published var items: [MovingReminderPresentation] = []
}

@MainActor
private final class WaitingOverlayStore: ObservableObject {
    @Published var reminders: [ReminderItem]
    @Published var displayedReminder: ReminderItem?
    @Published var animation: CharacterAnimation?
    @Published var collapseGeneration = 0
    @Published var characterHeight: CGFloat
    let movesRight: Bool

    init(
        reminders: [ReminderItem],
        animation: CharacterAnimation?,
        movesRight: Bool,
        characterHeight: CGFloat
    ) {
        self.reminders = reminders
        displayedReminder = reminders.first
        self.animation = animation
        self.movesRight = movesRight
        self.characterHeight = characterHeight
    }
}

private struct MovingOverlayView: View {
    @ObservedObject var store: MovingOverlayStore

    var body: some View {
        GeometryReader { _ in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                ForEach(store.items) { item in
                    movingItem(item, at: timeline.date)
                }
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private func movingItem(_ item: MovingReminderPresentation, at date: Date) -> some View {
        let elapsed = max(0, date.timeIntervalSince(item.startDate))
        let progress = date < item.startDate ? 0 : min(1, elapsed / item.duration)
        let point = item.route.point(at: progress)
        let frameIndex = item.animation?.frameIndex(at: elapsed) ?? 0
        let image = item.animation.flatMap { animation in
            animation.frames.indices.contains(frameIndex) ? animation.frames[frameIndex] : nil
        }

        ReminderBubble(
            reminder: item.reminder,
            image: image,
            mirrorsForDirection: item.animation?.mirrorsForDirection == true,
            movesRight: item.route.movesRight,
            frameIndex: frameIndex,
            characterHeight: item.characterHeight
        )
        .position(point)
    }
}

private struct ReminderBubble: View {
    let reminder: ReminderItem
    let image: NSImage?
    let mirrorsForDirection: Bool
    let movesRight: Bool
    let frameIndex: Int
    let characterHeight: CGFloat

    var body: some View {
        let text = Text(reminder.title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PinglyTheme.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(PinglyTheme.greenSoft.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(PinglyTheme.green.opacity(0.48), lineWidth: 0.8)
                    )
            )

        if let image {
            let character = Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: characterHeight, height: characterHeight)
                .scaleEffect(x: mirrorsForDirection && !movesRight ? -1 : 1, y: 1)
                .offset(y: mirrorsForDirection && frameIndex != 0 ? -2 : 0)

            switch reminder.textPosition {
            case .above: VStack(spacing: 3) { text; character }
            case .below: VStack(spacing: 3) { character; text }
            case .behind:
                if movesRight { HStack(spacing: 4) { text; character } }
                else { HStack(spacing: 4) { character; text } }
            case .ahead:
                if movesRight { HStack(spacing: 4) { character; text } }
                else { HStack(spacing: 4) { text; character } }
            }
        } else {
            text
        }
    }
}

private struct WaitingReminderView: View {
    @ObservedObject var store: WaitingOverlayStore
    let onComplete: (ReminderItem) -> Void
    let onSnooze: (ReminderItem) -> Void
    let onViewAll: () -> Void
    let onExpansionChanged: (Bool) -> Void

    @State private var isHovered = false
    @State private var isPinnedOpen = false

    private var showsActions: Bool { isHovered || isPinnedOpen }

    var body: some View {
        Group {
            if let reminder = store.displayedReminder {
                reminderContent(reminder).id(reminder.id)
            }
        }
        .onChange(of: store.collapseGeneration) { _ in
            isHovered = false
            isPinnedOpen = false
            onExpansionChanged(false)
        }
    }

    private func reminderContent(_ reminder: ReminderItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let animation = store.animation {
                    TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                        let elapsed = timeline.date.timeIntervalSinceReferenceDate
                        let index = animation.frameIndex(at: elapsed)
                        let image = animation.frames.indices.contains(index)
                            ? animation.frames[index]
                            : nil
                        ReminderBubble(
                            reminder: reminder,
                            image: image,
                            mirrorsForDirection: animation.mirrorsForDirection,
                            movesRight: store.movesRight,
                            frameIndex: index,
                            characterHeight: store.characterHeight
                        )
                    }
                } else {
                    ReminderBubble(
                        reminder: reminder,
                        image: nil,
                        mirrorsForDirection: false,
                        movesRight: store.movesRight,
                        frameIndex: 0,
                        characterHeight: store.characterHeight
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if showsActions {
                    isHovered = false
                    isPinnedOpen = false
                    onExpansionChanged(false)
                    NSCursor.arrow.set()
                } else {
                    isPinnedOpen = true
                }
            }

            if showsActions {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button("完成") { onComplete(reminder) }
                            .buttonStyle(.borderedProminent)
                            .tint(PinglyTheme.green)
                        Button("稍后提醒") { onSnooze(reminder) }
                            .buttonStyle(.bordered)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Button(action: onViewAll) {
                        HStack {
                            Spacer(minLength: 0)
                            Text("查看全部提醒")
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(PinglyTheme.green)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
            }
        }
        .background(
            Group {
                if showsActions {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(PinglyTheme.greenSoft.opacity(0.97))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(PinglyTheme.green.opacity(0.55), lineWidth: 1)
                        )
                }
            }
        )
        .padding(4)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            (hovering ? NSCursor.openHand : NSCursor.arrow).set()
            if !isPinnedOpen {
                onExpansionChanged(hovering)
            }
        }
        .onChange(of: isPinnedOpen) { pinned in
            onExpansionChanged(pinned || isHovered)
        }
    }
}

struct OverlayRoute {
    let start: CGPoint
    let end: CGPoint

    var movesRight: Bool { end.x > start.x }
    var distance: CGFloat { hypot(end.x - start.x, end.y - start.y) }

    func point(at progress: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    func isNearlyIdentical(to other: OverlayRoute) -> Bool {
        abs(start.x - other.start.x) < 24 &&
            abs(start.y - other.start.y) < 24 &&
            abs(end.x - other.end.x) < 24 &&
            abs(end.y - other.end.y) < 24
    }

    static func make(style: ReminderRouteStyle, in size: CGSize) -> OverlayRoute {
        let outside: CGFloat = 38
        let left = -outside
        let right = size.width + outside
        let centerY = size.height / 2
        let fixedLaneOffset: CGFloat = 24
        let safeLow = max(90, size.height * 0.20)
        let safeHigh = min(size.height - 90, size.height * 0.80)
        let randomY = CGFloat.random(in: safeLow...max(safeLow, safeHigh))

        switch style {
        case .centerLeftToRight:
            return .init(
                start: CGPoint(x: left, y: centerY - fixedLaneOffset),
                end: CGPoint(x: right, y: centerY - fixedLaneOffset)
            )
        case .centerRightToLeft:
            return .init(
                start: CGPoint(x: right, y: centerY + fixedLaneOffset),
                end: CGPoint(x: left, y: centerY + fixedLaneOffset)
            )
        case .randomHorizontal:
            return .init(start: CGPoint(x: left, y: randomY), end: CGPoint(x: right, y: randomY))
        case .randomDiagonal:
            var secondY = CGFloat.random(in: safeLow...max(safeLow, safeHigh))
            if abs(secondY - randomY) < size.height * 0.18 {
                secondY = randomY < centerY ? safeHigh : safeLow
            }
            return .init(start: CGPoint(x: left, y: randomY), end: CGPoint(x: right, y: secondY))
        case .fullyRandom:
            let movesRight = Bool.random()
            let secondY = CGFloat.random(in: safeLow...max(safeLow, safeHigh))
            return movesRight
                ? .init(start: CGPoint(x: left, y: randomY), end: CGPoint(x: right, y: secondY))
                : .init(start: CGPoint(x: right, y: randomY), end: CGPoint(x: left, y: secondY))
        }
    }
}
