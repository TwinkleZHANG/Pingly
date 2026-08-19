import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            PinglySidebar()
                .frame(width: 168)

            Rectangle()
                .fill(PinglyTheme.border)
                .frame(width: 1)

            VStack(spacing: 0) {
                PinglyDetailTopBar()
                Rectangle()
                    .fill(PinglyTheme.border)
                    .frame(height: 1)

                Group {
                    if store.isShowingOnboarding {
                        OnboardingView()
                    } else {
                        switch store.selectedPage {
                        case .reminders:
                            ReminderListView()
                        case .characters:
                            CharacterLibraryView()
                        case .settings:
                            SettingsView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PinglyTheme.window)
            }
        }
        .background(PinglyTheme.window)
        .ignoresSafeArea(.container, edges: .top)
        .task {
            if !store.hasCompletedOnboarding {
                store.isShowingOnboarding = true
            }
        }
    }
}

private struct PinglyDetailTopBar: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(store.isPaused ? PinglyTheme.apricot : PinglyTheme.green)
                    .frame(width: 8, height: 8)
                Text(store.isPaused ? "提醒已暂停" : "提醒运行中")
                    .foregroundStyle(PinglyTheme.secondaryText)
            }
            .font(.callout)

            HStack {
                Spacer()
                PauseMenuButton()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(PinglyTheme.window)
    }
}

private struct PinglySidebar: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 32)

            HStack {
                Text("Pingly")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 28)

            VStack(spacing: 6) {
                ForEach(SidebarPage.allCases) { page in
                    Button {
                        store.selectedPage = page
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.systemImage)
                                .frame(width: 18)
                            Text(page.title)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
                        .foregroundStyle(store.selectedPage == page ? PinglyTheme.green : PinglyTheme.primaryText)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(store.selectedPage == page ? PinglyTheme.window : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(10)
        }
        .background(PinglyTheme.sidebar)
    }
}

private struct PauseMenuButton: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            if store.isPaused {
                Button("继续提醒") { store.resume() }
            } else {
                Button("暂停 30 分钟") { store.pause(for: 30 * 60) }
                Button("暂停 1 小时") { store.pause(for: 60 * 60) }
                Button("今天不再提醒") { store.pauseForRestOfToday() }
                Divider()
                Button("自定义时长…") {}
            }
        } label: {
            Label(store.isPaused ? "继续" : "暂停", systemImage: store.isPaused ? "play.fill" : "pause.fill")
                .padding(.horizontal, 11)
                .frame(height: 32)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct ReminderListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isCreatingReminder = false
    @State private var editingReminder: ReminderItem?
    @State private var filter: ReminderListFilter = .all

    private var displayedReminderIDs: [UUID] {
        let matching = store.reminders.filter { reminder in
            switch filter {
            case .all: true
            case .interval: reminder.kind == .interval
            case .scheduled: reminder.kind == .scheduled
            }
        }
        let originalOrder = Dictionary(
            uniqueKeysWithValues: store.reminders.enumerated().map { ($0.element.id, $0.offset) }
        )
        let intervals = matching
            .filter { $0.kind == .interval }
            .sorted { lhs, rhs in
                let leftMinutes = lhs.intervalMinutes ?? 5
                let rightMinutes = rhs.intervalMinutes ?? 5
                if leftMinutes != rightMinutes { return leftMinutes < rightMinutes }
                return (originalOrder[lhs.id] ?? 0) < (originalOrder[rhs.id] ?? 0)
            }
        let scheduled = matching
            .filter { $0.kind == .scheduled }
            .sorted { lhs, rhs in
                switch (lhs.scheduledDate, rhs.scheduledDate) {
                case let (left?, right?) where left != right:
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return (originalOrder[lhs.id] ?? 0) < (originalOrder[rhs.id] ?? 0)
                }
            }
        return (intervals + scheduled).map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let editingReminder {
                NewReminderView(
                    reminder: editingReminder,
                    onCancel: { self.editingReminder = nil },
                    onComplete: { self.editingReminder = nil }
                )
            } else if isCreatingReminder {
                NewReminderView(
                    onCancel: { isCreatingReminder = false },
                    onComplete: { isCreatingReminder = false }
                )
            } else {
                PageHeader(
                    title: "提醒",
                    subtitle: nil,
                    actionTitle: "新建提醒",
                    systemImage: "plus"
                ) { isCreatingReminder = true }

                if store.reminders.isEmpty {
                    EmptyStateView(
                        systemImage: "bell.badge",
                        title: "还没有提醒",
                        message: "创建第一条提醒，让角色在合适的时间出现。",
                        buttonTitle: "新建提醒"
                    ) { isCreatingReminder = true }
                } else {
                    HStack {
                        Picker("提醒筛选", selection: $filter) {
                            ForEach(ReminderListFilter.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 204)
                        .controlSize(.small)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(displayedReminderIDs, id: \.self) { reminderID in
                                if let index = store.reminders.firstIndex(where: { $0.id == reminderID }) {
                                    ReminderRow(
                                        reminder: $store.reminders[index],
                                        onEdit: {
                                            editingReminder = store.reminders[index]
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }
}

private enum ReminderListFilter: String, CaseIterable, Identifiable {
    case all
    case interval
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .interval: "间隔"
        case .scheduled: "定时"
        }
    }
}

private struct ReminderRow: View {
    @EnvironmentObject private var store: AppStore
    @Binding var reminder: ReminderItem
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Toggle("", isOn: $reminder.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(PinglyTheme.green)

            Button(action: onEdit) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 9) {
                            Text(reminder.kind.title)
                                .font(.caption)
                                .frame(width: 54)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(reminder.kind == .scheduled ? PinglyTheme.apricotSoft : PinglyTheme.greenSoft)
                                )
                            Text(reminder.title).fontWeight(.semibold)
                        }
                        Text(reminder.summary(timeFormat: store.timeDisplayFormat))
                            .font(.callout)
                            .foregroundStyle(PinglyTheme.secondaryText)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(PinglyTheme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("编辑提醒")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(PinglyTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PinglyTheme.border, lineWidth: 1)
                )
        )
    }
}

struct CharacterLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isChoosingImportMethod = false
    @State private var isImporting = false
    @State private var isImportingHatchPet = false
    @State private var editingCharacter: CharacterProfile?

    var body: some View {
        VStack(spacing: 0) {
            if let editingCharacter {
                if editingCharacter.assetFormat == .hatchPetAtlas {
                    HatchPetImportView(
                        character: editingCharacter,
                        onCancel: { self.editingCharacter = nil },
                        onComplete: { self.editingCharacter = nil }
                    )
                } else {
                    CharacterImportView(
                        character: editingCharacter,
                        onCancel: { self.editingCharacter = nil },
                        onComplete: { self.editingCharacter = nil }
                    )
                }
            } else if isChoosingImportMethod {
                CharacterImportMethodView(
                    onChoosePosePNGs: {
                        isChoosingImportMethod = false
                        isImporting = true
                    },
                    onChooseHatchPet: {
                        isChoosingImportMethod = false
                        isImportingHatchPet = true
                    },
                    onCancel: { isChoosingImportMethod = false }
                )
            } else if isImportingHatchPet {
                HatchPetImportView(
                    onCancel: { isImportingHatchPet = false },
                    onComplete: { isImportingHatchPet = false }
                )
            } else if isImporting {
                CharacterImportView(
                    onCancel: { isImporting = false },
                    onComplete: { isImporting = false }
                )
            } else {
                PageHeader(
                    title: "我的角色",
                    subtitle: "最多保存 6 个角色，固定使用一个或随机选择。",
                    actionTitle: store.characters.count < 6 ? "添加角色" : nil,
                    systemImage: store.characters.count < 6 ? "square.and.arrow.down" : nil
                ) { if store.characters.count < 6 { isChoosingImportMethod = true } }

                if store.characters.isEmpty {
                    EmptyStateView(
                        systemImage: "sparkles",
                        title: "还没有角色",
                        message: "可以导入 hatch-pet 动画包，也可继续逐张导入透明 PNG。",
                        buttonTitle: "添加角色"
                    ) { isChoosingImportMethod = true }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("提醒时使用").fontWeight(.semibold)
                                    Text(store.selectionMode == .fixed ? "每次使用选中的角色" : "每次从已加入随机的角色中选择")
                                        .font(.caption)
                                        .foregroundStyle(PinglyTheme.secondaryText)
                                }
                                Spacer()
                                Picker("提醒时使用", selection: $store.selectionMode) {
                                    Text("固定角色").tag(CharacterSelectionMode.fixed)
                                    Text("随机角色").tag(CharacterSelectionMode.random)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(PinglyTheme.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(PinglyTheme.border))
                            )

                            ForEach($store.characters) { $character in
                                HStack(spacing: 14) {
                                    Button {
                                        editingCharacter = character
                                    } label: {
                                        HStack(spacing: 14) {
                                        characterPreview(character: character)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(character.name).fontWeight(.semibold)
                                            Text(character.assetSummary)
                                                .foregroundStyle(PinglyTheme.secondaryText)
                                        }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    if store.selectionMode == .random {
                                        Toggle("加入随机", isOn: $character.isIncludedInRandomPool)
                                            .toggleStyle(.switch)
                                            .tint(PinglyTheme.green)
                                            .fixedSize()
                                    } else {
                                        Button {
                                            store.selectedCharacterID = character.id
                                        } label: {
                                            Image(systemName: store.selectedCharacterID == character.id ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(store.selectedCharacterID == character.id ? PinglyTheme.green : PinglyTheme.secondaryText)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Button {
                                        editingCharacter = character
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .frame(width: 24, height: 28)
                                            .foregroundStyle(PinglyTheme.secondaryText)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(PinglyTheme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(store.selectedCharacterID == character.id && store.selectionMode == .fixed ? PinglyTheme.green : PinglyTheme.border)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }

    private func characterPreview(character: CharacterProfile) -> some View {
        Group {
            if let image = CharacterAnimationLoader.previewImage(for: character) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(PinglyTheme.green)
            }
        }
        .frame(width: 56, height: 56)
        .background(PinglyTheme.greenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var destination: SettingsDestination?
    @State private var selectedCalibrationDisplayID = ""

    var body: some View {
        Group {
            switch destination {
            case .sound: soundSettings
            case .display: displaySettings
            case nil: rootSettings
            }
        }
        .alert("设置未更新", isPresented: Binding(
            get: { store.settingsErrorMessage != nil },
            set: { if !$0 { store.settingsErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.settingsErrorMessage = nil }
        } message: {
            Text(store.settingsErrorMessage ?? "请稍后重试。")
        }
    }

    private var rootSettings: some View {
        VStack(spacing: 0) {
            PageHeader(title: "设置", subtitle: "只保留会影响日常使用的全局选项")

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("时间显示").fontWeight(.semibold)
                            Text("应用内所有时间的输入和显示方式")
                                .foregroundStyle(PinglyTheme.secondaryText)
                        }
                        Spacer()
                        Picker("时间显示", selection: $store.timeDisplayFormat) {
                            ForEach(TimeDisplayFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }
                    .padding(.vertical, 15)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(PinglyTheme.border).frame(height: 1)
                    }

                    SettingToggleRow(
                        title: "登录后自动启动",
                        detail: "登录 Mac 后在菜单栏运行",
                        isOn: Binding(
                            get: { store.launchAtLogin },
                            set: { store.setLaunchAtLogin($0) }
                        )
                    )
                    SettingToggleRow(
                        title: "屏幕共享时隐藏",
                        detail: "阻止提醒浮层被截屏或窗口共享捕获",
                        isOn: $store.hideDuringScreenShare
                    )
                    SettingToggleRow(
                        title: "全屏应用中显示",
                        detail: "全屏工作时仍然提醒",
                        isOn: $store.showInFullScreen
                    )
                    SettingLinkRow(
                        title: "声音与专注模式",
                        detail: store.soundEnabled ? store.reminderSound.title : "默认静音",
                        action: { destination = .sound }
                    )
                    SettingLinkRow(
                        title: "显示与主题",
                        detail: String(format: "%.1f cm · %@", store.characterDisplayHeightCentimeters, store.accentTheme.title),
                        action: { destination = .display }
                    )
                    Button("重新显示首次引导") { store.isShowingOnboarding = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(PinglyTheme.green)
                        .padding(.vertical, 18)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var soundSettings: some View {
        settingsSubpage(title: "声音与专注模式") {
            SettingToggleRow(
                title: "提醒声音",
                detail: "默认关闭；开启后每次提醒出现时播放",
                isOn: $store.soundEnabled
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("系统提示音").fontWeight(.semibold)
                    Text("使用 macOS 内置声音")
                        .foregroundStyle(PinglyTheme.secondaryText)
                }
                Spacer()
                Picker("系统提示音", selection: $store.reminderSound) {
                    ForEach(ReminderSoundChoice.allCases) { sound in
                        Text(sound.title).tag(sound)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                Button("试听") { ReminderSoundPlayer.play(store.reminderSound) }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 15)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PinglyTheme.border).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("专注模式", systemImage: "moon.fill")
                    .fontWeight(.semibold)
                Text("macOS 不向普通 App 开放当前专注模式状态，Pingly 无法可靠地自动判断。需要安静时，可在菜单栏中快速暂停 30 分钟、1 小时或今天剩余时间。")
                    .foregroundStyle(PinglyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 16)
        }
    }

    private var displaySettings: some View {
        settingsSubpage(title: "显示与主题") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("角色显示高度").fontWeight(.semibold)
                        Text(String(format: "当前 %.1f cm，会立即应用到提醒浮层", store.characterDisplayHeightCentimeters))
                            .foregroundStyle(PinglyTheme.secondaryText)
                    }
                    Spacer()
                    Button("恢复默认") { store.characterDisplayHeightCentimeters = 2.0 }
                        .buttonStyle(.plain)
                        .foregroundStyle(PinglyTheme.green)
                }
                Slider(value: $store.characterDisplayHeightCentimeters, in: 1.2...3.0, step: 0.1) {
                    Text("角色高度")
                } minimumValueLabel: {
                    Text("小").font(.caption)
                } maximumValueLabel: {
                    Text("大").font(.caption)
                }
                .tint(PinglyTheme.green)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PinglyTheme.border).frame(height: 1)
            }

            if let calibrationScreen {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("屏幕厘米校准").fontWeight(.semibold)
                            Text("用实体直尺对照下方 5 cm 标尺")
                                .foregroundStyle(PinglyTheme.secondaryText)
                        }
                        Spacer()
                        if NSScreen.screens.count > 1 {
                            Picker("显示器", selection: $selectedCalibrationDisplayID) {
                                ForEach(NSScreen.screens, id: \.self) { screen in
                                    Text(screen.localizedName)
                                        .tag(store.displayIdentifier(for: screen))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                    }

                    Capsule()
                        .fill(PinglyTheme.green)
                        .frame(width: min(420, store.pointsPerCentimeter(for: calibrationScreen) * 5), height: 5)

                    HStack {
                        Text("短").font(.caption)
                        Slider(
                            value: Binding(
                                get: { store.calibrationScale(for: calibrationScreen) },
                                set: { store.setCalibrationScale($0, for: calibrationScreen) }
                            ),
                            in: 0.7...1.4,
                            step: 0.01
                        )
                        .tint(PinglyTheme.green)
                        Text("长").font(.caption)
                        Button("重置") { store.setCalibrationScale(1, for: calibrationScreen) }
                            .buttonStyle(.plain)
                            .foregroundStyle(PinglyTheme.green)
                    }
                }
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PinglyTheme.border).frame(height: 1)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("主题色").fontWeight(.semibold)
                Picker("主题色", selection: $store.accentTheme) {
                    ForEach(PinglyAccentTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .padding(.vertical, 16)
        }
        .onAppear {
            if selectedCalibrationDisplayID.isEmpty, let screen = NSScreen.main ?? NSScreen.screens.first {
                selectedCalibrationDisplayID = store.displayIdentifier(for: screen)
            }
        }
    }

    private var calibrationScreen: NSScreen? {
        NSScreen.screens.first {
            store.displayIdentifier(for: $0) == selectedCalibrationDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func settingsSubpage<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { destination = nil } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(title).font(.title2).fontWeight(.semibold)
                Spacer()
            }
            .padding(24)

            ScrollView {
                VStack(spacing: 0) { content() }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
    }
}

private enum SettingsDestination {
    case sound
    case display
}

private struct SettingToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(PinglyTheme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(PinglyTheme.green)
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PinglyTheme.border).frame(height: 1)
        }
    }
}

private struct SettingLinkRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).foregroundStyle(PinglyTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(PinglyTheme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PinglyTheme.border).frame(height: 1)
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String?
    var actionTitle: String?
    var systemImage: String?
    var action: (() -> Void)?

    init(
        title: String,
        subtitle: String?,
        actionTitle: String? = nil,
        systemImage: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2).fontWeight(.semibold)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).foregroundStyle(PinglyTheme.secondaryText)
                }
            }
            Spacer()
            if let actionTitle, let systemImage, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: systemImage)
                }
                .buttonStyle(.borderedProminent)
                .tint(PinglyTheme.green)
            }
        }
        .padding(24)
    }
}

private struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        Spacer()
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(PinglyTheme.green)
            Text(title).font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(PinglyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(PinglyTheme.green)
        }
        Spacer()
    }
}
