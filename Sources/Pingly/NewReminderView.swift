import SwiftUI

struct NewReminderView: View {
    @EnvironmentObject private var store: AppStore

    let onCancel: () -> Void
    let onComplete: () -> Void
    private let editingID: UUID?
    private let originalIsEnabled: Bool

    @State private var step = 0
    @State private var title = ""
    @State private var kind: ReminderKind = .interval
    @State private var intervalMinutes = 5
    @State private var scheduledDate = Date().addingTimeInterval(60 * 60)
    @State private var repeatRule: ReminderRepeatRule = .none
    @State private var activeDateScope: ActiveDateScope = .always
    @State private var activeStartDate = Date()
    @State private var activeEndDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var usesActiveHours = false
    @State private var activeStartTime = Self.time(hour: 9)
    @State private var activeEndTime = Self.time(hour: 18)
    @State private var routeStyle: ReminderRouteStyle = .centerLeftToRight
    @State private var movementSpeed: ReminderMovementSpeed = .normal
    @State private var textPosition: ReminderTextPosition = .behind
    @State private var scheduledDisplayBehavior: ScheduledDisplayBehavior = .sameAsInterval
    @State private var snoozeMinutes = 10
    @State private var isConfirmingDelete = false
    @State private var previewMessage: String?
    @State private var isShowingIntervalLimitAlert = false

    private let stepTitles = ["提醒内容", "出现时间", "呈现方式", "确认"]

    init(reminder: ReminderItem? = nil, onCancel: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onComplete = onComplete
        editingID = reminder?.id
        originalIsEnabled = reminder?.isEnabled ?? true

        _title = State(initialValue: reminder?.title ?? "")
        _kind = State(initialValue: reminder?.kind ?? .interval)
        _intervalMinutes = State(initialValue: reminder?.intervalMinutes ?? 5)
        _scheduledDate = State(initialValue: reminder?.scheduledDate ?? Date().addingTimeInterval(60 * 60))
        _repeatRule = State(initialValue: reminder?.repeatRule ?? .none)
        _activeDateScope = State(initialValue: reminder?.activeDateScope ?? .always)
        _activeStartDate = State(initialValue: reminder?.activeStartDate ?? Date())
        _activeEndDate = State(initialValue: reminder?.activeEndDate ?? Date().addingTimeInterval(7 * 24 * 60 * 60))
        _usesActiveHours = State(initialValue: reminder?.usesActiveHours ?? false)
        _activeStartTime = State(initialValue: reminder?.activeStartTime ?? Self.time(hour: 9))
        _activeEndTime = State(initialValue: reminder?.activeEndTime ?? Self.time(hour: 18))
        _routeStyle = State(initialValue: reminder?.routeStyle ?? .centerLeftToRight)
        _movementSpeed = State(initialValue: reminder?.movementSpeed ?? .normal)
        _textPosition = State(initialValue: reminder?.textPosition ?? .behind)
        _scheduledDisplayBehavior = State(initialValue: reminder?.scheduledDisplayBehavior ?? .sameAsInterval)
        _snoozeMinutes = State(initialValue: reminder?.snoozeMinutes ?? 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                Group {
                    switch step {
                    case 0: contentStep
                    case 1: timingStep
                    case 2: appearanceStep
                    default: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PinglyTheme.window)
        .onChange(of: title) { newValue in
            if newValue.count > 18 {
                title = String(newValue.prefix(18))
            }
        }
        .onAppear {
            if editingID == nil,
               kind == .interval,
               !store.canAddIntervalReminder(replacing: nil) {
                kind = .scheduled
                isShowingIntervalLimitAlert = true
            }
        }
        .alert("最多添加 3 条间隔提醒", isPresented: $isShowingIntervalLimitAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("如需创建新的间隔提醒，请先删除或将现有的间隔提醒改为定时提醒。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editingID == nil ? "新建提醒" : "编辑提醒")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PinglyTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(stepTitles.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? PinglyTheme.green : PinglyTheme.border)
                        .frame(height: 4)
                }
            }

            Text("第 \(step + 1) 步，共 4 步 · \(stepTitles[step])")
                .font(.caption)
                .foregroundStyle(PinglyTheme.secondaryText)
        }
        .padding(22)
    }

    private var contentStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle("想让 Pingly 提醒什么？", detail: "提醒文字最多 18 个字，会跟着角色一起移动。")

            VStack(alignment: .leading, spacing: 7) {
                TextField("例如：眨眨眼睛", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                HStack {
                    Text(title.isEmpty ? "这行文字会出现在角色旁边" : "预览：\(title)")
                    Spacer()
                    Text("\(title.count)/18")
                }
                .font(.caption)
                .foregroundStyle(PinglyTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("提醒类型").fontWeight(.semibold)
                choiceCard(
                    title: "每隔一段时间",
                    detail: "适合眨眼、喝水、起身活动",
                    systemImage: "repeat",
                    isSelected: kind == .interval
                ) {
                    if store.canAddIntervalReminder(replacing: editingID) {
                        kind = .interval
                    } else {
                        isShowingIntervalLimitAlert = true
                    }
                }
                choiceCard(
                    title: "在指定时间",
                    detail: "适合会议、交资料或一次性事项",
                    systemImage: "calendar.badge.clock",
                    isSelected: kind == .scheduled
                ) { kind = .scheduled }
            }
        }
    }

    @ViewBuilder
    private var timingStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            if kind == .interval {
                sectionTitle("多久出现一次？", detail: "Pingly 只会在电脑开机且未休眠时运行。")

                HStack {
                    Text("每隔").fontWeight(.semibold)
                    Spacer()
                    HStack(spacing: 6) {
                        TextField("", value: $intervalMinutes, formatter: Self.intervalIntegerFormatter)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 58)
                        Text("分钟")
                        Stepper("", value: $intervalMinutes, in: 1...240)
                            .labelsHidden()
                    }
                    .fixedSize()
                }
                .settingBox()

                labeledPicker("在哪些日期生效", selection: $activeDateScope, values: ActiveDateScope.allCases)

                if activeDateScope == .dateRange {
                    VStack(spacing: 12) {
                        DatePicker("开始日期", selection: $activeStartDate, displayedComponents: .date)
                        DatePicker("结束日期", selection: $activeEndDate, in: activeStartDate..., displayedComponents: .date)
                    }
                    .settingBox()
                }

                Toggle("只在每天的固定时间段内提醒", isOn: $usesActiveHours)
                    .toggleStyle(.switch)
                    .tint(PinglyTheme.green)

                if usesActiveHours {
                    VStack(spacing: 12) {
                        ClockTimeEditor(
                            label: "从",
                            date: $activeStartTime,
                            format: store.timeDisplayFormat
                        )
                        Rectangle().fill(PinglyTheme.border).frame(height: 1)
                        ClockTimeEditor(
                            label: "到",
                            date: $activeEndTime,
                            format: store.timeDisplayFormat
                        )
                    }
                    .settingBox()
                }
            } else {
                sectionTitle("什么时候提醒？", detail: "到点后可以直接经过屏幕，或停下来等你处理。")

                ScheduledDateTimeEditor(
                    date: $scheduledDate,
                    format: store.timeDisplayFormat
                )

                labeledPicker("重复", selection: $repeatRule, values: ReminderRepeatRule.allCases, width: 118)
            }
        }
    }

    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("角色怎样经过屏幕？", detail: "默认从屏幕中央左侧走到右侧，以后也可以再修改。")

            labeledPicker("移动路线", selection: $routeStyle, values: ReminderRouteStyle.allCases)
            labeledPicker("移动速度", selection: $movementSpeed, values: ReminderMovementSpeed.allCases)
            labeledPicker("文字位置", selection: $textPosition, values: ReminderTextPosition.allCases)

            if kind == .scheduled {
                labeledPicker(
                    "到点后的行为",
                    selection: $scheduledDisplayBehavior,
                    values: ScheduledDisplayBehavior.allCases
                )

                if scheduledDisplayBehavior == .waitForAction {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("稍后提醒").fontWeight(.semibold)
                            Text("点击角色后可选择完成或稍后提醒")
                                .font(.caption)
                                .foregroundStyle(PinglyTheme.secondaryText)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            TextField("", value: $snoozeMinutes, formatter: Self.integerFormatter)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 52)
                            Text("分钟")
                            Stepper("", value: $snoozeMinutes, in: 1...120)
                                .labelsHidden()
                        }
                        .fixedSize()
                    }
                    .settingBox()
                }
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                sectionTitle("可以创建了", detail: "先在真实屏幕上预览，再保存这条提醒。")
                Spacer()
                Button {
                    preview()
                } label: {
                    Label("预览效果", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .tint(PinglyTheme.green)
            }

            if let previewMessage {
                Label(previewMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(PinglyTheme.secondaryText)
            }

            VStack(spacing: 0) {
                reviewRow("提醒", value: title.trimmingCharacters(in: .whitespacesAndNewlines))
                reviewRow("类型", value: kind.title)
                reviewRow("时间", value: timingSummary)
                reviewRow("路线", value: routeStyle.title)
                reviewRow("速度", value: movementSpeed.title)
                reviewRow("文字", value: textPosition.title, showsDivider: false)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(PinglyTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(PinglyTheme.border))
            )

            Label("屏幕上始终只有一个角色；角色被定时提醒占用时，间隔提醒会以最多 3 条纯文字继续运行。", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(PinglyTheme.secondaryText)
        }
    }

    private var footer: some View {
        HStack {
            Button(step == 0 ? "取消" : "上一步") {
                if step == 0 { onCancel() } else { step -= 1 }
            }
            .keyboardShortcut(.cancelAction)

            if editingID != nil && step == 0 {
                Button(isConfirmingDelete ? "再次点击确认删除" : "删除提醒") {
                    if isConfirmingDelete {
                        if let editingID { store.deleteReminder(id: editingID) }
                        onComplete()
                    } else {
                        isConfirmingDelete = true
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
            }

            Spacer()

            if step < 3 {
                Button("继续") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .tint(PinglyTheme.green)
                    .disabled(step == 0 && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(editingID == nil ? "创建提醒" : "保存修改") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(PinglyTheme.green)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    private var timingSummary: String {
        if kind == .interval {
            var result = "每 \(intervalMinutes) 分钟 · \(activeDateScope.title)"
            if usesActiveHours {
                result += " · \(store.timeDisplayFormat.timeString(from: activeStartTime))–\(store.timeDisplayFormat.timeString(from: activeEndTime))"
            }
            return result
        }
        return "\(store.timeDisplayFormat.dateTimeString(from: scheduledDate, includesYear: true)) · \(repeatRule.title)"
    }

    private func save() {
        let reminder = draftReminder
        let didSave: Bool
        if editingID == nil {
            didSave = store.addReminder(reminder)
        } else {
            didSave = store.updateReminder(reminder)
        }
        guard didSave else {
            isShowingIntervalLimitAlert = true
            return
        }
        onComplete()
    }

    private var draftReminder: ReminderItem {
        ReminderItem(
            id: editingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            isEnabled: originalIsEnabled,
            intervalMinutes: kind == .interval ? intervalMinutes : nil,
            scheduledDate: kind == .scheduled ? scheduledDate : nil,
            repeatRule: kind == .scheduled ? repeatRule : .none,
            activeDateScope: activeDateScope,
            activeStartDate: activeDateScope == .dateRange || activeDateScope == .today ? activeStartDate : nil,
            activeEndDate: activeDateScope == .dateRange ? activeEndDate : nil,
            usesActiveHours: kind == .interval && usesActiveHours,
            activeStartTime: usesActiveHours ? activeStartTime : nil,
            activeEndTime: usesActiveHours ? activeEndTime : nil,
            routeStyle: routeStyle,
            movementSpeed: movementSpeed,
            textPosition: textPosition,
            scheduledDisplayBehavior: scheduledDisplayBehavior,
            snoozeMinutes: snoozeMinutes
        )
    }

    private func preview() {
        let character = store.characterForNextAppearance
        let didShow = ReminderOverlayCoordinator.shared.showPreview(reminder: draftReminder, character: character)
        previewMessage = didShow
            ? (draftReminder.kind == .scheduled && draftReminder.scheduledDisplayBehavior == .waitForAction
                ? "正在预览候停等待；点击完成或稍后提醒可结束本次预览。"
                : (character == nil
                    ? "当前没有角色，正在预览独立移动的提醒文字。"
                    : "预览正在鼠标当前所在的屏幕上播放。"))
            : "预览未能打开，请稍后重试。"
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2).fontWeight(.semibold)
            Text(detail).foregroundStyle(PinglyTheme.secondaryText)
        }
    }

    private func choiceCard(
        title: String,
        detail: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? PinglyTheme.green : PinglyTheme.secondaryText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).font(.callout).foregroundStyle(PinglyTheme.secondaryText)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? PinglyTheme.green : PinglyTheme.secondaryText)
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? PinglyTheme.greenSoft : PinglyTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? PinglyTheme.green : PinglyTheme.border, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func labeledPicker<Value: Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Value>,
        values: [Value],
        width: CGFloat = 250
    ) -> some View where Value: RawRepresentable, Value.RawValue == String {
        HStack {
            Text(title).fontWeight(.semibold)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values) { value in
                    Text(pickerTitle(for: value)).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: width)
        }
        .settingBox()
    }

    private func pickerTitle<Value>(for value: Value) -> String {
        switch value {
        case let value as ActiveDateScope: value.title
        case let value as ReminderRepeatRule: value.title
        case let value as ReminderRouteStyle: value.title
        case let value as ReminderMovementSpeed: value.title
        case let value as ReminderTextPosition: value.title
        case let value as ScheduledDisplayBehavior: value.title
        default: ""
        }
    }

    private func reviewRow(_ label: String, value: String, showsDivider: Bool = true) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(PinglyTheme.secondaryText).frame(width: 54, alignment: .leading)
            Text(value).fontWeight(.medium)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(PinglyTheme.border).frame(height: 1) }
        }
    }

    private static func time(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 120
        return formatter
    }()

    private static let intervalIntegerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 240
        return formatter
    }()
}

private struct ScheduledDateTimeEditor: View {
    @Binding var date: Date
    let format: TimeDisplayFormat

    @State private var day: String
    @State private var month: String
    @State private var year: String

    init(date: Binding<Date>, format: TimeDisplayFormat) {
        _date = date
        self.format = format
        let value = date.wrappedValue
        let components = Calendar.current.dateComponents([.day, .month, .year], from: value)
        _day = State(initialValue: String(format: "%02d", components.day ?? 1))
        _month = State(initialValue: String(format: "%02d", components.month ?? 1))
        _year = State(initialValue: String(components.year ?? 2026))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("日期").fontWeight(.semibold)
                Spacer()
                HStack(spacing: 5) {
                    numberField("日", text: $day, width: 38, limit: 2)
                    Text("/").foregroundStyle(PinglyTheme.secondaryText)
                    numberField("月", text: $month, width: 38, limit: 2)
                    Text("/").foregroundStyle(PinglyTheme.secondaryText)
                    numberField("年", text: $year, width: 62, limit: 4)
                }
            }

            Rectangle().fill(PinglyTheme.border).frame(height: 1)
            ClockTimeEditor(label: "时间", date: $date, format: format)
        }
        .settingBox()
        .onChange(of: day) { _ in updateDate() }
        .onChange(of: month) { _ in updateDate() }
        .onChange(of: year) { _ in updateDate() }
    }

    private func numberField(_ placeholder: String, text: Binding<String>, width: CGFloat, limit: Int) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .onChange(of: text.wrappedValue) { newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue || digits.count > limit {
                    text.wrappedValue = String(digits.prefix(limit))
                }
            }
    }

    private func updateDate() {
        guard let dayValue = Int(day),
              let monthValue = Int(month),
              let yearValue = Int(year),
              (1...31).contains(dayValue),
              (1...12).contains(monthValue) else { return }

        var components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        components.calendar = .current
        components.timeZone = TimeZone.current
        components.year = yearValue
        components.month = monthValue
        components.day = dayValue

        if let updated = Calendar.current.date(from: components) {
            date = updated
        }
    }
}

private struct ClockTimeEditor: View {
    let label: String
    @Binding var date: Date
    let format: TimeDisplayFormat
    var showsExplanation = true

    @State private var period: DayPeriod
    @State private var hour: String
    @State private var minute: String

    init(
        label: String,
        date: Binding<Date>,
        format: TimeDisplayFormat,
        showsExplanation: Bool = true
    ) {
        self.label = label
        _date = date
        self.format = format
        self.showsExplanation = showsExplanation

        let components = Calendar.current.dateComponents([.hour, .minute], from: date.wrappedValue)
        let hour24 = components.hour ?? 9
        _period = State(initialValue: DayPeriod(hour24: hour24))
        _hour = State(initialValue: Self.hourText(hour24: hour24, format: format))
        _minute = State(initialValue: String(format: "%02d", components.minute ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).fontWeight(.semibold)
                Spacer()

                if format == .twelveHour {
                    Picker("时段", selection: $period) {
                        ForEach(DayPeriod.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }

                HStack(spacing: 4) {
                    numberField("时", text: $hour, width: 42, limit: 2)
                    Text(":").fontWeight(.semibold)
                    numberField("分", text: $minute, width: 42, limit: 2)
                }
            }

            if format == .twelveHour && showsExplanation {
                Text("上午 12:00 是凌晨，下午 12:00 是中午。")
                    .font(.caption)
                    .foregroundStyle(PinglyTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onChange(of: period) { _ in updateTime() }
        .onChange(of: hour) { _ in updateTime() }
        .onChange(of: minute) { _ in updateTime() }
        .onChange(of: format) { _ in syncFromDate() }
    }

    private func numberField(
        _ placeholder: String,
        text: Binding<String>,
        width: CGFloat,
        limit: Int
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .onChange(of: text.wrappedValue) { newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue || digits.count > limit {
                    text.wrappedValue = String(digits.prefix(limit))
                }
            }
    }

    private func updateTime() {
        guard let hourValue = Int(hour),
              let minuteValue = Int(minute),
              (0...59).contains(minuteValue) else { return }

        let hour24: Int
        switch format {
        case .twentyFourHour:
            guard (0...23).contains(hourValue) else { return }
            hour24 = hourValue
        case .twelveHour:
            guard (1...12).contains(hourValue) else { return }
            hour24 = period.hour24(from: hourValue)
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .second], from: date)
        components.calendar = calendar
        components.timeZone = TimeZone.current
        components.hour = hour24
        components.minute = minuteValue
        if let updated = calendar.date(from: components), updated != date {
            date = updated
        }
    }

    private func syncFromDate() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour24 = components.hour ?? 0
        period = DayPeriod(hour24: hour24)
        hour = Self.hourText(hour24: hour24, format: format)
        minute = String(format: "%02d", components.minute ?? 0)
    }

    private static func hourText(hour24: Int, format: TimeDisplayFormat) -> String {
        switch format {
        case .twentyFourHour: String(format: "%02d", hour24)
        case .twelveHour: String(format: "%02d", DayPeriod.displayHour(from: hour24))
        }
    }
}

private enum DayPeriod: String, CaseIterable, Identifiable {
    case morning
    case afternoon

    var id: String { rawValue }
    var title: String {
        switch self {
        case .morning: "上午"
        case .afternoon: "下午"
        }
    }

    init(hour24: Int) {
        if hour24 < 12 { self = .morning }
        else { self = .afternoon }
    }

    static func displayHour(from hour24: Int) -> Int {
        if hour24 == 0 || hour24 == 12 { return 12 }
        return hour24 > 12 ? hour24 - 12 : hour24
    }

    func hour24(from displayHour: Int) -> Int {
        switch self {
        case .morning: displayHour == 12 ? 0 : displayHour
        case .afternoon: displayHour == 12 ? 12 : displayHour + 12
        }
    }
}

extension View {
    func settingBox() -> some View {
        padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(PinglyTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(PinglyTheme.border))
            )
    }
}
