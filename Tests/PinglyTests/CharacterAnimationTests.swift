import AppKit
import XCTest
@testable import Pingly

final class CharacterAnimationTests: XCTestCase {
    func testDelayedUpdatesStillVisitEveryFrameInOrder() {
        let animation = makeAnimation(frameCount: 8)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var playback = SequentialFramePlayback()

        playback.start(animation: animation, at: start)

        let visited = (1...8).map { step in
            playback.advance(
                animation: animation,
                at: start.addingTimeInterval(TimeInterval(step) * 0.5)
            )
        }

        XCTAssertEqual(visited, [1, 2, 3, 4, 5, 6, 7, 0])
    }

    func testFrameDoesNotAdvanceBeforeItsDurationEnds() {
        let animation = makeAnimation(frameCount: 8)
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        var playback = SequentialFramePlayback()

        playback.start(animation: animation, at: start)

        XCTAssertEqual(
            playback.advance(animation: animation, at: start.addingTimeInterval(0.119)),
            0
        )
        XCTAssertEqual(
            playback.advance(animation: animation, at: start.addingTimeInterval(0.120)),
            1
        )
    }

    func testReplacingAnimationRestartsFromFirstFrame() {
        let first = makeAnimation(frameCount: 8)
        let replacement = makeAnimation(frameCount: 8)
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        var playback = SequentialFramePlayback()

        playback.start(animation: first, at: start)
        XCTAssertEqual(
            playback.advance(animation: first, at: start.addingTimeInterval(0.5)),
            1
        )
        XCTAssertEqual(
            playback.advance(animation: replacement, at: start.addingTimeInterval(0.6)),
            0
        )
    }

    private func makeAnimation(frameCount: Int) -> CharacterAnimation {
        CharacterAnimation(
            frames: (0..<frameCount).map { _ in NSImage(size: NSSize(width: 1, height: 1)) },
            frameDurations: Array(repeating: 0.12, count: frameCount),
            mirrorsForDirection: false
        )
    }
}
