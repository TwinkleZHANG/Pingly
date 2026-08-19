import Foundation

enum PinglyAccentTheme: String, Codable, CaseIterable, Identifiable {
    case sage
    case apricot
    case blue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sage: "鼠尾草绿"
        case .apricot: "杏桃橙"
        case .blue: "雾蓝"
        }
    }
}

enum ReminderSoundChoice: String, Codable, CaseIterable, Identifiable {
    case glass = "Glass"
    case ping = "Ping"
    case pop = "Pop"
    case submarine = "Submarine"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: "玻璃"
        case .ping: "叮"
        case .pop: "气泡"
        case .submarine: "水声"
        }
    }
}

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case interval
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interval: "间隔提醒"
        case .scheduled: "定时提醒"
        }
    }
}

struct ReminderItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var kind: ReminderKind
    var isEnabled: Bool = true
    var intervalMinutes: Int?
    var scheduledDate: Date?
    var repeatRule: ReminderRepeatRule = .none
    var activeDateScope: ActiveDateScope = .always
    var activeStartDate: Date?
    var activeEndDate: Date?
    var usesActiveHours: Bool = false
    var activeStartTime: Date?
    var activeEndTime: Date?
    var routeStyle: ReminderRouteStyle = .centerLeftToRight
    var movementSpeed: ReminderMovementSpeed = .normal
    var textPosition: ReminderTextPosition = .behind
    var scheduledDisplayBehavior: ScheduledDisplayBehavior = .sameAsInterval
    var snoozeMinutes: Int = 10

    var nextFireDate: Date? {
        kind == .scheduled ? scheduledDate : nil
    }

    func summary(timeFormat: TimeDisplayFormat) -> String {
        switch kind {
        case .interval:
            let interval = intervalMinutes ?? 5
            let scope = activeDateScope.title
            return "每 \(interval) 分钟 · \(scope) · \(movementSpeed.title)"
        case .scheduled:
            guard let scheduledDate else { return "尚未设置时间" }
            let repeatText = repeatRule == .none ? "不重复" : repeatRule.title
            return "\(timeFormat.dateTimeString(from: scheduledDate, includesYear: false)) · \(repeatText)"
        }
    }
}

enum TimeDisplayFormat: String, Codable, CaseIterable, Identifiable {
    case twentyFourHour
    case twelveHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twentyFourHour: "24 小时制"
        case .twelveHour: "上午 / 下午"
        }
    }

    func timeString(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = components.hour ?? 0
        let minute = components.minute ?? 0
        switch self {
        case .twentyFourHour:
            return String(format: "%02d:%02d", hour24, minute)
        case .twelveHour:
            let period = hour24 < 12 ? "上午" : "下午"
            let displayHour = hour24 % 12 == 0 ? 12 : hour24 % 12
            return String(format: "%@ %d:%02d", period, displayHour, minute)
        }
    }

    func dateTimeString(
        from date: Date,
        includesYear: Bool,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let datePart = includesYear
            ? "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
            : "\(components.month ?? 0)月\(components.day ?? 0)日"
        return "\(datePart) \(timeString(from: date, calendar: calendar))"
    }
}

enum ReminderRepeatRule: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "不重复"
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }
}

enum ActiveDateScope: String, Codable, CaseIterable, Identifiable {
    case always
    case today
    case dateRange

    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: "一直生效"
        case .today: "仅今天"
        case .dateRange: "指定日期范围"
        }
    }
}

enum ReminderRouteStyle: String, Codable, CaseIterable, Identifiable {
    case centerLeftToRight
    case centerRightToLeft
    case randomHorizontal
    case randomDiagonal
    case fullyRandom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .centerLeftToRight: "屏幕中央，从左向右"
        case .centerRightToLeft: "屏幕中央，从右向左"
        case .randomHorizontal: "随机水平线"
        case .randomDiagonal: "随机斜线"
        case .fullyRandom: "完全随机"
        }
    }
}

enum ReminderMovementSpeed: String, Codable, CaseIterable, Identifiable {
    case slow
    case normal
    // 仅用于兼容早期保存的数据，不再显示为可选项。
    case fast

    static var allCases: [ReminderMovementSpeed] { [.normal, .slow] }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .slow: "慢速（约 22～30 秒）"
        case .normal: "正常（约 16～22 秒）"
        case .fast: "正常（约 16～22 秒）"
        }
    }

    func duration(for distance: CGFloat, textOnly: Bool) -> TimeInterval {
        let basePointsPerSecond: CGFloat
        let limits: ClosedRange<TimeInterval>
        switch self {
        case .slow:
            basePointsPerSecond = 60
            limits = 22...30
        case .normal, .fast:
            basePointsPerSecond = 85
            limits = 16...22
        }

        let adjustedSpeed = textOnly ? basePointsPerSecond * 0.9 : basePointsPerSecond
        let calculated = TimeInterval(distance / adjustedSpeed)
        return min(limits.upperBound, max(limits.lowerBound, calculated))
    }
}

enum ReminderTextPosition: String, Codable, CaseIterable, Identifiable {
    case behind
    case ahead
    case above
    case below

    var id: String { rawValue }
    var title: String {
        switch self {
        case .behind: "角色后方"
        case .ahead: "角色前方"
        case .above: "角色上方"
        case .below: "角色下方"
        }
    }
}

enum ScheduledDisplayBehavior: String, Codable, CaseIterable, Identifiable {
    case sameAsInterval
    case waitForAction

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sameAsInterval: "完成路线后自动离开"
        case .waitForAction: "到候停点等待处理"
        }
    }
}

enum CharacterAssetFormat: String, Codable, CaseIterable, Identifiable {
    case posePNGs
    case hatchPetAtlas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posePNGs: "独立 PNG 姿势"
        case .hatchPetAtlas: "hatch-pet 动画包"
        }
    }
}

struct CharacterProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var enabledActions: [CharacterAction]
    var assetPaths: [String: String]
    var isIncludedInRandomPool: Bool = true
    var assetFormat: CharacterAssetFormat = .posePNGs
    var hatchPetSpritesheetPath: String?
    var hatchPetManifestPath: String?

    var poseCount: Int {
        assetFormat == .hatchPetAtlas ? 62 : assetPaths.count
    }

    var actionCount: Int {
        assetFormat == .hatchPetAtlas ? 2 : enabledActions.count
    }

    var assetSummary: String {
        switch assetFormat {
        case .posePNGs: "\(poseCount) 张姿势 · \(actionCount) 个动作"
        case .hatchPetAtlas: "hatch-pet 图集 · 移动 + 原地动画"
        }
    }

    var previewImagePath: String? {
        switch assetFormat {
        case .posePNGs: assetPaths["move_1"] ?? assetPaths.values.first
        case .hatchPetAtlas: hatchPetSpritesheetPath
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        enabledActions: [CharacterAction],
        assetPaths: [String: String],
        isIncludedInRandomPool: Bool = true,
        assetFormat: CharacterAssetFormat = .posePNGs,
        hatchPetSpritesheetPath: String? = nil,
        hatchPetManifestPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.enabledActions = enabledActions
        self.assetPaths = assetPaths
        self.isIncludedInRandomPool = isIncludedInRandomPool
        self.assetFormat = assetFormat
        self.hatchPetSpritesheetPath = hatchPetSpritesheetPath
        self.hatchPetManifestPath = hatchPetManifestPath
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case enabledActions
        case assetPaths
        case isIncludedInRandomPool
        case assetFormat
        case hatchPetSpritesheetPath
        case hatchPetManifestPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        enabledActions = try container.decodeIfPresent([CharacterAction].self, forKey: .enabledActions) ?? [.movement]
        assetPaths = try container.decodeIfPresent([String: String].self, forKey: .assetPaths) ?? [:]
        isIncludedInRandomPool = try container.decodeIfPresent(Bool.self, forKey: .isIncludedInRandomPool) ?? true
        assetFormat = try container.decodeIfPresent(CharacterAssetFormat.self, forKey: .assetFormat) ?? .posePNGs
        hatchPetSpritesheetPath = try container.decodeIfPresent(String.self, forKey: .hatchPetSpritesheetPath)
        hatchPetManifestPath = try container.decodeIfPresent(String.self, forKey: .hatchPetManifestPath)
    }
}

enum CharacterAction: String, Codable, CaseIterable, Identifiable, Hashable {
    case movement
    case jump
    case sit
    case wave
    case celebrate
    case lickPaw
    case tailWag
    case chase
    case rest

    var id: String { rawValue }
    var title: String {
        switch self {
        case .movement: "移动"
        case .jump: "跳跃"
        case .sit: "坐下与等待"
        case .wave: "打招呼"
        case .celebrate: "开心庆祝"
        case .lickPaw: "舔爪子"
        case .tailWag: "摇尾巴"
        case .chase: "追逐小物体"
        case .rest: "趴下休息"
        }
    }

    var detail: String {
        switch self {
        case .movement: "必须提供两张交替姿势，用于走路、跑步和快速离开。"
        case .jump: "蓄力、腾空、落地。"
        case .sit: "坐下过程、停留、重新站起。"
        case .wave: "两个招手姿势交替播放。"
        case .celebrate: "准备、开心动作、回到自然姿势。"
        case .lickPaw: "爪子靠近嘴边、伸舌舔爪子；与坐姿组合播放。"
        case .tailWag: "两个尾巴位置交替播放；正面或侧面都可以。"
        case .chase: "两个移动姿势；追逐物必须画在同一张角色 PNG 内。"
        case .rest: "趴下过程、休息姿势、重新起身。"
        }
    }

    var poses: [CharacterPoseRequirement] {
        switch self {
        case .movement:
            [
                .init(id: "move_1", title: "移动姿势 1", instruction: "侧面朝向移动方向，一侧腿或身体摆动到第一位置。"),
                .init(id: "move_2", title: "移动姿势 2", instruction: "同样大小和位置，另一侧腿或身体摆动到第二位置。")
            ]
        case .jump:
            [
                .init(id: "jump_ready", title: "跳跃·蓄力", instruction: "身体下沉，呈现即将起跳的姿势。"),
                .init(id: "jump_air", title: "跳跃·腾空", instruction: "角色完全离地，动作轮廓清楚。"),
                .init(id: "jump_land", title: "跳跃·落地", instruction: "落地缓冲，身体略微降低；不要拉伸变形。")
            ]
        case .sit:
            [
                .init(id: "sit_down", title: "坐下·过渡", instruction: "从自然姿势开始坐下的中间状态。"),
                .init(id: "sit_hold", title: "坐下·停留", instruction: "稳定坐姿，用于等待用户处理提醒。"),
                .init(id: "sit_up", title: "坐下·起身", instruction: "从坐姿重新站起的中间状态。")
            ]
        case .wave:
            [
                .init(id: "wave_1", title: "打招呼 1", instruction: "抬起手、爪或身体的一部分准备打招呼。"),
                .init(id: "wave_2", title: "打招呼 2", instruction: "挥向另一侧；与第一张交替时自然。")
            ]
        case .celebrate:
            [
                .init(id: "celebrate_1", title: "庆祝·准备", instruction: "开心动作开始前的自然准备姿势。"),
                .init(id: "celebrate_2", title: "庆祝·动作", instruction: "最有辨识度的开心或庆祝姿势。"),
                .init(id: "celebrate_3", title: "庆祝·结束", instruction: "动作收回，准备继续移动。")
            ]
        case .lickPaw:
            [
                .init(id: "lick_ready", title: "舔爪·靠近", instruction: "坐姿，爪子或肢体抬到嘴边。"),
                .init(id: "lick_tongue", title: "舔爪·伸舌", instruction: "保持同一角度，伸出舌头舔爪子。")
            ]
        case .tailWag:
            [
                .init(id: "tail_1", title: "摇尾巴 1", instruction: "尾巴位于摆动的一侧；角色可以正面或侧面。"),
                .init(id: "tail_2", title: "摇尾巴 2", instruction: "尾巴摆到另一侧，其余外形尽量一致。")
            ]
        case .chase:
            [
                .init(id: "chase_1", title: "追逐姿势 1", instruction: "侧面移动姿势；小物体必须画在同一张透明 PNG 中。"),
                .init(id: "chase_2", title: "追逐姿势 2", instruction: "第二个移动姿势；小物体位置随动作自然变化。")
            ]
        case .rest:
            [
                .init(id: "rest_down", title: "休息·趴下", instruction: "从自然姿势开始趴下的过渡状态。"),
                .init(id: "rest_hold", title: "休息·停留", instruction: "稳定、放松的趴卧姿势。"),
                .init(id: "rest_up", title: "休息·起身", instruction: "从趴卧状态重新起身。")
            ]
        }
    }
}

struct CharacterPoseRequirement: Identifiable, Hashable {
    let id: String
    let title: String
    let instruction: String
}

enum CharacterSelectionMode: String, Codable {
    case fixed
    case random
}

enum SidebarPage: String, CaseIterable, Identifiable {
    case reminders
    case characters
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reminders: "提醒"
        case .characters: "我的角色"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .reminders: "bell"
        case .characters: "sparkles"
        case .settings: "gearshape"
        }
    }
}
