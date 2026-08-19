import AppKit
import Combine
import Foundation

struct CharacterAnimation {
    let playbackID = UUID()
    let frames: [NSImage]
    let frameDurations: [TimeInterval]
    let mirrorsForDirection: Bool
    let usesLayerBackedFrames: Bool

    init(
        frames: [NSImage],
        frameDurations: [TimeInterval],
        mirrorsForDirection: Bool,
        usesLayerBackedFrames: Bool = false
    ) {
        self.frames = frames
        self.frameDurations = frameDurations
        self.mirrorsForDirection = mirrorsForDirection
        self.usesLayerBackedFrames = usesLayerBackedFrames
    }

    func frameDuration(at index: Int) -> TimeInterval {
        guard frames.indices.contains(index) else { return 0.16 }
        let duration = frameDurations.count == frames.count
            ? frameDurations[index]
            : 0.16
        return duration > 0 ? duration : 0.16
    }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        guard !frames.isEmpty else { return 0 }
        let durations = frameDurations.count == frames.count
            ? frameDurations
            : Array(repeating: 0.16, count: frames.count)
        let cycleDuration = durations.reduce(0, +)
        guard cycleDuration > 0 else { return 0 }

        var position = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        for (index, duration) in durations.enumerated() {
            if position < duration { return index }
            position -= duration
        }
        return frames.count - 1
    }
}

struct SequentialFramePlayback {
    private(set) var frameIndex = 0
    private var nextFrameDate: Date?
    private var animationID: UUID?

    mutating func start(animation: CharacterAnimation, at date: Date) {
        animationID = animation.playbackID
        frameIndex = 0
        nextFrameDate = date.addingTimeInterval(animation.frameDuration(at: 0))
    }

    @discardableResult
    mutating func advance(animation: CharacterAnimation, at date: Date) -> Int {
        guard !animation.frames.isEmpty else {
            animationID = animation.playbackID
            frameIndex = 0
            nextFrameDate = nil
            return 0
        }

        guard animationID == animation.playbackID, let nextFrameDate else {
            start(animation: animation, at: date)
            return frameIndex
        }

        guard date >= nextFrameDate else { return frameIndex }

        // Advance by exactly one frame. TimelineView callbacks are not
        // guaranteed to arrive on time, so deriving the index from absolute
        // elapsed time can skip short hatch-pet frames after a delayed refresh.
        frameIndex = (frameIndex + 1) % animation.frames.count
        self.nextFrameDate = date.addingTimeInterval(animation.frameDuration(at: frameIndex))
        return frameIndex
    }
}

final class SequentialAnimationPlaybackController: ObservableObject {
    let animation: CharacterAnimation?
    @Published private(set) var frameIndex = 0

    private var playback = SequentialFramePlayback()
    private var timer: Timer?

    init(animation: CharacterAnimation?, startDate: Date) {
        self.animation = animation
        guard let animation, !animation.frames.isEmpty else { return }

        let effectiveStartDate = max(startDate, Date())
        playback.start(animation: animation, at: effectiveStartDate)
        scheduleNext(
            after: effectiveStartDate.timeIntervalSinceNow + animation.frameDuration(at: 0)
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advanceOneFrame() {
        guard let animation else { return }

        // The timer is one-shot and the state machine advances once per fire.
        // A late main-thread callback pauses the animation instead of catching
        // up by skipping intermediate frames.
        frameIndex = playback.advance(animation: animation, at: Date())
        scheduleNext(after: animation.frameDuration(at: frameIndex))
    }

    private func scheduleNext(after delay: TimeInterval) {
        timer?.invalidate()

        let nextTimer = Timer(timeInterval: max(0.001, delay), repeats: false) { [weak self] _ in
            self?.advanceOneFrame()
        }
        nextTimer.tolerance = 0
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }
}

enum HatchPetState: Int, CaseIterable {
    case idle = 0
    case runningRight = 1
    case runningLeft = 2
    case waving = 3
    case jumping = 4
    case failed = 5
    case waiting = 6
    case running = 7
    case review = 8

    var isDirectionalMovement: Bool {
        self == .runningRight || self == .runningLeft
    }

    var frameDurations: [TimeInterval] {
        switch self {
        case .idle: [0.28, 0.11, 0.11, 0.14, 0.14, 0.32]
        // Pingly moves the sprite across a large desktop route at the same
        // time as it changes poses. Give every directional stride equal,
        // readable screen time so neither leg is perceptually favored.
        case .runningRight, .runningLeft: [0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18]
        case .waving: [0.14, 0.14, 0.14, 0.28]
        case .jumping: [0.14, 0.14, 0.14, 0.14, 0.28]
        case .failed: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24]
        case .waiting: [0.15, 0.15, 0.15, 0.15, 0.15, 0.26]
        case .running: [0.12, 0.12, 0.12, 0.12, 0.12, 0.22]
        case .review: [0.15, 0.15, 0.15, 0.15, 0.15, 0.28]
        }
    }
}

enum HatchPetAtlas {
    static let columns = 8
    static let rows = 9
    static let cellWidth = 192
    static let cellHeight = 208
    static let pixelWidth = columns * cellWidth
    static let pixelHeight = rows * cellHeight

    // hatch-pet rows 1 and 2 are reserved exclusively for matching horizontal
    // travel. Every other state is stationary in Pingly.
    static let stationaryStates = HatchPetState.allCases.filter { !$0.isDirectionalMovement }

    static func pixelSize(of image: NSImage) -> CGSize? {
        guard let source = cgImage(from: image) else { return nil }
        return CGSize(width: source.width, height: source.height)
    }

    static func animation(at path: String, state: HatchPetState) -> CharacterAnimation? {
        guard let atlas = NSImage(contentsOfFile: path),
              let source = cgImage(from: atlas),
              source.width == pixelWidth,
              source.height == pixelHeight else { return nil }

        let count = state.frameDurations.count
        var frames: [NSImage] = []
        frames.reserveCapacity(count)

        for column in 0..<count {
            let rect = CGRect(
                x: column * cellWidth,
                y: state.rawValue * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
            guard let cropped = source.cropping(to: rect) else { return nil }
            frames.append(
                NSImage(
                    cgImage: cropped,
                    size: NSSize(width: cellWidth, height: cellHeight)
                )
            )
        }

        return CharacterAnimation(
            frames: frames,
            frameDurations: state.frameDurations,
            mirrorsForDirection: false,
            usesLayerBackedFrames: true
        )
    }

    static func movementAnimation(at path: String, movesRight: Bool) -> CharacterAnimation? {
        let state: HatchPetState = movesRight ? .runningRight : .runningLeft
        return animation(at: path, state: state)
    }

    static func stationaryAnimation(at path: String, state: HatchPetState? = nil) -> CharacterAnimation? {
        let selectedState = state.flatMap { $0.isDirectionalMovement ? nil : $0 }
            ?? stationaryStates.randomElement()
            ?? .idle
        return animation(at: path, state: selectedState)
    }

    static func previewImage(at path: String) -> NSImage? {
        animation(at: path, state: .idle)?.frames.first
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

enum CharacterAnimationLoader {
    static func movementAnimation(for character: CharacterProfile?, movesRight: Bool) -> CharacterAnimation? {
        guard let character else { return nil }

        switch character.assetFormat {
        case .posePNGs:
            guard let firstPath = character.assetPaths["move_1"],
                  let secondPath = character.assetPaths["move_2"],
                  let firstImage = NSImage(contentsOfFile: firstPath),
                  let secondImage = NSImage(contentsOfFile: secondPath) else { return nil }
            return CharacterAnimation(
                frames: [firstImage, secondImage],
                frameDurations: [0.22, 0.22],
                mirrorsForDirection: true
            )

        case .hatchPetAtlas:
            guard let path = character.hatchPetSpritesheetPath else { return nil }
            return HatchPetAtlas.movementAnimation(at: path, movesRight: movesRight)
        }
    }

    static func stationaryAnimation(for character: CharacterProfile?, state: HatchPetState? = nil) -> CharacterAnimation? {
        guard let character else { return nil }

        switch character.assetFormat {
        case .posePNGs:
            let preferredPoseIDs = ["sit_hold", "rest_hold", "wave_1", "move_1"]
            let path = preferredPoseIDs.compactMap { character.assetPaths[$0] }.first
                ?? character.assetPaths.values.first
            guard let path,
                  let image = NSImage(contentsOfFile: path) else { return nil }
            return CharacterAnimation(frames: [image], frameDurations: [1], mirrorsForDirection: true)
        case .hatchPetAtlas:
            guard let path = character.hatchPetSpritesheetPath else { return nil }
            return HatchPetAtlas.stationaryAnimation(at: path, state: state)
        }
    }

    static func attentionAnimation(for character: CharacterProfile?) -> CharacterAnimation? {
        guard let character else { return nil }

        switch character.assetFormat {
        case .posePNGs:
            guard let firstPath = character.assetPaths["wave_1"],
                  let secondPath = character.assetPaths["wave_2"],
                  let firstImage = NSImage(contentsOfFile: firstPath),
                  let secondImage = NSImage(contentsOfFile: secondPath) else {
                return stationaryAnimation(for: character)
            }
            return CharacterAnimation(
                frames: [firstImage, secondImage],
                frameDurations: [0.24, 0.24],
                mirrorsForDirection: true
            )
        case .hatchPetAtlas:
            guard let path = character.hatchPetSpritesheetPath else { return nil }
            return HatchPetAtlas.stationaryAnimation(at: path)
        }
    }

    static func previewImage(for character: CharacterProfile) -> NSImage? {
        switch character.assetFormat {
        case .posePNGs:
            guard let path = character.previewImagePath else { return nil }
            return NSImage(contentsOfFile: path)
        case .hatchPetAtlas:
            guard let path = character.hatchPetSpritesheetPath else { return nil }
            return HatchPetAtlas.previewImage(at: path)
        }
    }
}
