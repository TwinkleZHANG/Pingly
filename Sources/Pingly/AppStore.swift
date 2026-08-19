import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    static let maximumIntervalReminderCount = 3

    @Published var reminders: [ReminderItem] = [] {
        didSet { saveRemindersIfReady() }
    }
    @Published var characters: [CharacterProfile] = [] {
        didSet { saveCharactersIfReady() }
    }
    @Published var selectedPage: SidebarPage = .reminders
    @Published var selectionMode: CharacterSelectionMode = .fixed
    @Published var selectedCharacterID: UUID?
    @Published var isShowingOnboarding = false
    @Published var pauseUntil: Date?

    @Published private(set) var launchAtLogin = false
    @Published var settingsErrorMessage: String?
    @Published var hideDuringScreenShare = true {
        didSet { saveGlobalSetting(hideDuringScreenShare, key: hideDuringScreenShareKey, updatesWindows: true) }
    }
    @Published var showInFullScreen = true {
        didSet { saveGlobalSetting(showInFullScreen, key: showInFullScreenKey, updatesWindows: true) }
    }
    @Published var soundEnabled = false {
        didSet { saveGlobalSetting(soundEnabled, key: soundEnabledKey) }
    }
    @Published var reminderSound: ReminderSoundChoice = .glass {
        didSet { saveGlobalSetting(reminderSound.rawValue, key: reminderSoundKey) }
    }
    @Published var characterDisplayHeightCentimeters: Double = 2.0 {
        didSet { saveGlobalSetting(characterDisplayHeightCentimeters, key: characterDisplayHeightKey, updatesWindows: true) }
    }
    @Published var displayCalibrationScales: [String: Double] = [:] {
        didSet { saveGlobalSetting(displayCalibrationScales, key: displayCalibrationScalesKey, updatesWindows: true) }
    }
    @Published var accentTheme: PinglyAccentTheme = .sage {
        didSet { saveGlobalSetting(accentTheme.rawValue, key: accentThemeKey, updatesWindows: true) }
    }
    @Published var timeDisplayFormat: TimeDisplayFormat = .twelveHour {
        didSet {
            guard hasLoadedPersistentData else { return }
            UserDefaults.standard.set(timeDisplayFormat.rawValue, forKey: timeDisplayFormatKey)
        }
    }

    private let onboardingKey = "hasCompletedOnboarding"
    private let remindersKey = "savedReminders.v1"
    private let charactersKey = "savedCharacters.v1"
    private let timeDisplayFormatKey = "timeDisplayFormat.v1"
    private let hideDuringScreenShareKey = "hideDuringScreenShare.v1"
    private let showInFullScreenKey = "showInFullScreen.v1"
    private let soundEnabledKey = "soundEnabled.v1"
    private let reminderSoundKey = "reminderSound.v1"
    private let characterDisplayHeightKey = "characterDisplayHeightCentimeters.v2"
    private let displayCalibrationScalesKey = "displayCalibrationScales.v1"
    static let accentThemeDefaultsKey = "accentTheme.v1"
    private var accentThemeKey: String { Self.accentThemeDefaultsKey }
    private var hasLoadedPersistentData = false

    init() {
        if let data = UserDefaults.standard.data(forKey: remindersKey),
           let decoded = try? JSONDecoder().decode([ReminderItem].self, from: data) {
            reminders = decoded.map { item in
                var migrated = item
                if migrated.movementSpeed == .fast {
                    migrated.movementSpeed = .normal
                }
                return migrated
            }
        }
        if let data = UserDefaults.standard.data(forKey: charactersKey),
           let decoded = try? JSONDecoder().decode([CharacterProfile].self, from: data) {
            characters = decoded
        }
        if let rawValue = UserDefaults.standard.string(forKey: timeDisplayFormatKey),
           let savedFormat = TimeDisplayFormat(rawValue: rawValue) {
            timeDisplayFormat = savedFormat
        }
        if UserDefaults.standard.object(forKey: hideDuringScreenShareKey) != nil {
            hideDuringScreenShare = UserDefaults.standard.bool(forKey: hideDuringScreenShareKey)
        }
        if UserDefaults.standard.object(forKey: showInFullScreenKey) != nil {
            showInFullScreen = UserDefaults.standard.bool(forKey: showInFullScreenKey)
        }
        if UserDefaults.standard.object(forKey: soundEnabledKey) != nil {
            soundEnabled = UserDefaults.standard.bool(forKey: soundEnabledKey)
        }
        if let rawValue = UserDefaults.standard.string(forKey: reminderSoundKey),
           let savedSound = ReminderSoundChoice(rawValue: rawValue) {
            reminderSound = savedSound
        }
        if UserDefaults.standard.object(forKey: characterDisplayHeightKey) != nil {
            characterDisplayHeightCentimeters = min(
                3,
                max(1.2, UserDefaults.standard.double(forKey: characterDisplayHeightKey))
            )
        }
        if let savedScales = UserDefaults.standard.dictionary(forKey: displayCalibrationScalesKey) as? [String: Double] {
            displayCalibrationScales = savedScales
        }
        if let rawValue = UserDefaults.standard.string(forKey: accentThemeKey),
           let savedTheme = PinglyAccentTheme(rawValue: rawValue) {
            accentTheme = savedTheme
        }
        launchAtLogin = Self.loginItemIsRegistered
        hasLoadedPersistentData = true
    }

    var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: onboardingKey)
    }

    var isPaused: Bool {
        guard let pauseUntil else { return false }
        return pauseUntil > Date()
    }

    var nextReminder: ReminderItem? {
        reminders
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                switch (lhs.nextFireDate, rhs.nextFireDate) {
                case let (left?, right?): left < right
                case (_?, nil): true
                default: false
                }
            }
            .first
    }

    var characterForNextAppearance: CharacterProfile? {
        switch selectionMode {
        case .fixed:
            if let selectedCharacterID,
               let selected = characters.first(where: { $0.id == selectedCharacterID }) {
                return selected
            }
            return characters.first
        case .random:
            return characters.filter(\.isIncludedInRandomPool).randomElement() ?? characters.first
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
        isShowingOnboarding = false
    }

    func pause(for interval: TimeInterval) {
        pauseUntil = Date().addingTimeInterval(interval)
    }

    func pauseForRestOfToday() {
        pauseUntil = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
    }

    func resume() {
        pauseUntil = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = Self.loginItemIsRegistered
            if SMAppService.mainApp.status == .requiresApproval {
                settingsErrorMessage = "已添加登录项，但需要在“系统设置 → 通用 → 登录项”中允许 Pingly。"
            }
        } catch {
            launchAtLogin = Self.loginItemIsRegistered
            settingsErrorMessage = "无法更新登录启动设置：\(error.localizedDescription)"
        }
    }

    func displayIdentifier(for screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.stringValue ?? String(describing: screen.frame)
    }

    func calibrationScale(for screen: NSScreen) -> Double {
        displayCalibrationScales[displayIdentifier(for: screen)] ?? 1
    }

    func setCalibrationScale(_ scale: Double, for screen: NSScreen) {
        displayCalibrationScales[displayIdentifier(for: screen)] = min(1.4, max(0.7, scale))
    }

    func pointsPerCentimeter(for screen: NSScreen) -> CGFloat {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 37.8 * calibrationScale(for: screen)
        }
        let millimeters = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value))
        let automatic = millimeters.width > 0
            ? screen.frame.width / (millimeters.width / 10)
            : 37.8
        return automatic * calibrationScale(for: screen)
    }

    func characterDisplayHeight(for screen: NSScreen?) -> CGFloat {
        let target = screen ?? NSScreen.main
        guard let target else { return CGFloat(characterDisplayHeightCentimeters * 37.8) }
        return CGFloat(characterDisplayHeightCentimeters) * pointsPerCentimeter(for: target)
    }

    private static var loginItemIsRegistered: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private func saveGlobalSetting<T>(_ value: T, key: String, updatesWindows: Bool = false) {
        guard hasLoadedPersistentData else { return }
        UserDefaults.standard.set(value, forKey: key)
        if updatesWindows {
            ReminderOverlayCoordinator.shared.applyWindowPreferences()
        }
    }

    @discardableResult
    func addReminder(_ reminder: ReminderItem) -> Bool {
        guard canAddIntervalReminder(replacing: nil) || reminder.kind != .interval else { return false }
        reminders.append(reminder)
        return true
    }

    @discardableResult
    func updateReminder(_ reminder: ReminderItem) -> Bool {
        guard canAddIntervalReminder(replacing: reminder.id) || reminder.kind != .interval,
              let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return false }
        reminders[index] = reminder
        return true
    }

    func canAddIntervalReminder(replacing reminderID: UUID?) -> Bool {
        let existingCount = reminders.filter {
            $0.kind == .interval && $0.id != reminderID
        }.count
        return existingCount < Self.maximumIntervalReminderCount
    }

    func deleteReminder(id: UUID) {
        reminders.removeAll { $0.id == id }
    }

    func addCharacter(
        name: String,
        actions: [CharacterAction],
        sourceData: [String: Data],
        includedInRandomPool: Bool
    ) throws {
        guard characters.count < 6 else { return }

        let id = UUID()
        let root = try characterStorageRoot()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var savedPaths: [String: String] = [:]
        for (poseID, data) in sourceData {
            let destination = folder.appendingPathComponent("\(poseID).png")
            try writeNormalizedPNG(data, to: destination)
            savedPaths[poseID] = destination.path
        }

        characters.append(
            CharacterProfile(
                id: id,
                name: name,
                enabledActions: actions,
                assetPaths: savedPaths,
                isIncludedInRandomPool: includedInRandomPool
            )
        )
        if selectedCharacterID == nil { selectedCharacterID = id }
    }

    func updateCharacter(
        id: UUID,
        name: String,
        actions: [CharacterAction],
        sourceData: [String: Data],
        includedInRandomPool: Bool
    ) throws {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { return }
        let root = try characterStorageRoot()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let retainedPoseIDs = Set(actions.flatMap { $0.poses.map(\.id) })
        if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files where !retainedPoseIDs.contains(file.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        var savedPaths: [String: String] = [:]
        for poseID in retainedPoseIDs {
            let destination = folder.appendingPathComponent("\(poseID).png")
            if let data = sourceData[poseID] {
                try writeNormalizedPNG(data, to: destination)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                savedPaths[poseID] = destination.path
            }
        }

        characters[index] = CharacterProfile(
            id: id,
            name: name,
            enabledActions: actions,
            assetPaths: savedPaths,
            isIncludedInRandomPool: includedInRandomPool
        )
    }

    func addHatchPetCharacter(
        packageURL: URL,
        nameOverride: String? = nil,
        includedInRandomPool: Bool
    ) throws {
        guard characters.count < 6 else { return }

        let id = UUID()
        let installed = try installHatchPetPackage(from: packageURL, characterID: id)
        let cleanOverride = nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanOverride?.isEmpty == false ? cleanOverride! : installed.displayName

        characters.append(
            CharacterProfile(
                id: id,
                name: name,
                enabledActions: [.movement],
                assetPaths: [:],
                isIncludedInRandomPool: includedInRandomPool,
                assetFormat: .hatchPetAtlas,
                hatchPetSpritesheetPath: installed.spritesheetPath,
                hatchPetManifestPath: installed.manifestPath
            )
        )
        if selectedCharacterID == nil { selectedCharacterID = id }
    }

    func updateHatchPetCharacter(
        id: UUID,
        name: String,
        replacementPackageURL: URL?,
        includedInRandomPool: Bool
    ) throws {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { return }
        let current = characters[index]
        let installed = try replacementPackageURL.map {
            try installHatchPetPackage(from: $0, characterID: id)
        }

        characters[index] = CharacterProfile(
            id: id,
            name: name,
            enabledActions: [.movement],
            assetPaths: [:],
            isIncludedInRandomPool: includedInRandomPool,
            assetFormat: .hatchPetAtlas,
            hatchPetSpritesheetPath: installed?.spritesheetPath ?? current.hatchPetSpritesheetPath,
            hatchPetManifestPath: installed?.manifestPath ?? current.hatchPetManifestPath
        )
    }

    func deleteCharacter(id: UUID) {
        if let root = try? characterStorageRoot() {
            let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
        }
        characters.removeAll { $0.id == id }
        if selectedCharacterID == id {
            selectedCharacterID = characters.first?.id
        }
    }

    private func saveRemindersIfReady() {
        guard hasLoadedPersistentData,
              let data = try? JSONEncoder().encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: remindersKey)
    }

    private func saveCharactersIfReady() {
        guard hasLoadedPersistentData,
              let data = try? JSONEncoder().encode(characters) else { return }
        UserDefaults.standard.set(data, forKey: charactersKey)
    }

    private func characterStorageRoot() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport.appendingPathComponent("Pingly/Characters", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func installHatchPetPackage(
        from packageURL: URL,
        characterID: UUID
    ) throws -> (displayName: String, spritesheetPath: String, manifestPath: String) {
        let package = packageURL.standardizedFileURL
        let manifestURL = package.appendingPathComponent("pet.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder().decode(HatchPetManifest.self, from: manifestData) else {
            throw CharacterStorageError.invalidHatchPetManifest
        }

        let relativeSpritesheetPath = manifest.spritesheetPath
        guard !relativeSpritesheetPath.isEmpty,
              !relativeSpritesheetPath.hasPrefix("/"),
              !relativeSpritesheetPath.split(separator: "/").contains("..") else {
            throw CharacterStorageError.invalidHatchPetManifest
        }

        let sourceSpritesheet = package
            .appendingPathComponent(relativeSpritesheetPath)
            .standardizedFileURL
        let packagePrefix = package.path.hasSuffix("/") ? package.path : package.path + "/"
        guard sourceSpritesheet.path.hasPrefix(packagePrefix),
              let image = NSImage(contentsOf: sourceSpritesheet),
              let size = HatchPetAtlas.pixelSize(of: image),
              Int(size.width) == HatchPetAtlas.pixelWidth,
              Int(size.height) == HatchPetAtlas.pixelHeight,
              let spritesheetData = try? Data(contentsOf: sourceSpritesheet) else {
            throw CharacterStorageError.invalidHatchPetSpritesheet
        }

        let root = try characterStorageRoot()
        let folder = root.appendingPathComponent(characterID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destinationSpritesheet = folder.appendingPathComponent("spritesheet.webp")
        let destinationManifest = folder.appendingPathComponent("pet.json")

        try spritesheetData.write(to: destinationSpritesheet, options: .atomic)
        manifest.spritesheetPath = "spritesheet.webp"
        let normalizedManifest = try JSONEncoder().encode(manifest)
        try normalizedManifest.write(to: destinationManifest, options: .atomic)

        return (
            manifest.displayName,
            destinationSpritesheet.path,
            destinationManifest.path
        )
    }

    private func writeNormalizedPNG(_ data: Data, to destination: URL) throws {
        guard let source = NSImage(data: data), source.size.width > 0, source.size.height > 0 else {
            throw CharacterStorageError.invalidPNG
        }

        let canvasSize = NSSize(width: 1024, height: 1024)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1024,
            pixelsHigh: 1024,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CharacterStorageError.cannotCreateImage
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let scale = min(canvasSize.width / source.size.width, canvasSize.height / source.size.height)
        let renderedSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let destinationRect = NSRect(
            x: (canvasSize.width - renderedSize.width) / 2,
            y: (canvasSize.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
        source.draw(in: destinationRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CharacterStorageError.cannotCreateImage
        }
        try png.write(to: destination, options: .atomic)
    }
}

private enum CharacterStorageError: LocalizedError {
    case invalidPNG
    case cannotCreateImage
    case invalidHatchPetManifest
    case invalidHatchPetSpritesheet

    var errorDescription: String? {
        switch self {
        case .invalidPNG: "无法读取其中一张 PNG 图片"
        case .cannotCreateImage: "无法生成角色图片的本地工作副本"
        case .invalidHatchPetManifest: "没有找到可用的 pet.json，或其内容不完整"
        case .invalidHatchPetSpritesheet: "spritesheet.webp 必须是 1536×1872 的完整 hatch-pet 图集"
        }
    }
}

private struct HatchPetManifest: Codable {
    var id: String?
    var displayName: String
    var description: String?
    var spritesheetPath: String
}
