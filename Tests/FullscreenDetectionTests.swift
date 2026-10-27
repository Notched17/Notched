// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import Notched

@Suite("Fullscreen detection")
struct FullscreenDetectionTests {
    // MARK: Managed display spaces (SkyLight)

    private func display(_ id: String, current: Int, spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": id, "Current Space": ["ManagedSpaceID": current], "Spaces": spaces]
    }

    @Test("A current space with a tile layout manager is fullscreen")
    func tileLayoutManagerMeansFullscreen() {
        let snapshot = [display("A", current: 7, spaces: [
            ["ManagedSpaceID": 1, "type": 0],
            ["ManagedSpaceID": 7, "type": 4, "TileLayoutManager": ["TileSpaces": []]],
        ])]
        #expect(ManagedSpaces.fullscreenDisplays(in: snapshot, mainDisplay: "A") == ["A"])
    }

    @Test("A current space of type 4 is fullscreen even without a tile layout manager")
    func typeFourMeansFullscreen() {
        let snapshot = [display("A", current: 7, spaces: [["ManagedSpaceID": 7, "type": 4]])]
        #expect(ManagedSpaces.fullscreenDisplays(in: snapshot, mainDisplay: "A") == ["A"])
    }

    @Test("An ordinary desktop space is not fullscreen")
    func desktopSpaceIsNotFullscreen() {
        let snapshot = [display("A", current: 1, spaces: [
            ["ManagedSpaceID": 1, "type": 0],
            ["ManagedSpaceID": 7, "type": 4, "TileLayoutManager": [:]],
        ])]
        #expect(ManagedSpaces.fullscreenDisplays(in: snapshot, mainDisplay: "A").isEmpty)
    }

    @Test("Each display is judged by its own current space")
    func perDisplay() {
        let snapshot = [
            display("A", current: 1, spaces: [["ManagedSpaceID": 1, "type": 0]]),
            display("B", current: 9, spaces: [["ManagedSpaceID": 9, "type": 4]]),
        ]
        #expect(ManagedSpaces.fullscreenDisplays(in: snapshot, mainDisplay: "A") == ["B"])
    }

    @Test("\"Main\" (displays share one set of Spaces) maps to the main display")
    func mainIdentifier() {
        let snapshot = [display("Main", current: 9, spaces: [["ManagedSpaceID": 9, "type": 4]])]
        #expect(ManagedSpaces.fullscreenDisplays(in: snapshot, mainDisplay: "A") == ["A"])
    }

    @Test("Malformed entries are ignored instead of crashing")
    func malformedEntries() {
        let snapshot: [[String: Any]] = [
            ["Display Identifier": "A"],
            ["Current Space": "nonsense", "Spaces": 3],
            display("B", current: 5, spaces: [["ManagedSpaceID": 6, "type": 4]]),
        ]
        #expect(ManagedSpaces.fullscreenDisplays(in: snapshot, mainDisplay: "A").isEmpty)
    }

    // MARK: Window-list heuristic (public fallback)

    /// Screens in Core Graphics coordinates (top-left origin of the primary display).
    static let screens: [(id: DisplayID, frame: CGRect)] = [
        ("BUILTIN", CGRect(x: 0, y: 0, width: 1920, height: 1243)),
        ("EXT", CGRect(x: 1920, y: -200, width: 2560, height: 1440)),
    ]

    private func window(_ frame: CGRect, layer: Int = 0, pid: Int32 = 500) -> WindowListFullscreenHeuristic.Window {
        .init(bounds: frame, layer: layer, ownerPID: pid)
    }

    @Test("A normal-layer window from another app covering a whole screen marks it fullscreen")
    func coveringWindow() {
        let windows = [window(CGRect(x: 0, y: 0, width: 1920, height: 1243))]
        #expect(WindowListFullscreenHeuristic.fullscreenDisplays(windows: windows, screens: Self.screens, ownPID: 1) == ["BUILTIN"])
    }

    @Test("A zoomed window that leaves the menu bar visible is not fullscreen")
    func zoomedWindow() {
        let windows = [window(CGRect(x: 0, y: 38, width: 1920, height: 1205))]
        #expect(WindowListFullscreenHeuristic.fullscreenDisplays(windows: windows, screens: Self.screens, ownPID: 1).isEmpty)
    }

    @Test("Notched's own windows and non-normal layers are ignored")
    func ignoresOwnAndOverlayWindows() {
        let windows = [
            window(CGRect(x: 0, y: 0, width: 1920, height: 1243), pid: 1),
            window(CGRect(x: 0, y: 0, width: 1920, height: 1243), layer: 25),
        ]
        #expect(WindowListFullscreenHeuristic.fullscreenDisplays(windows: windows, screens: Self.screens, ownPID: 1).isEmpty)
    }

    @Test("Only the screen the covering window is on is marked")
    func onlyMatchingScreen() {
        let windows = [window(CGRect(x: 1920, y: -200, width: 2560, height: 1440))]
        #expect(WindowListFullscreenHeuristic.fullscreenDisplays(windows: windows, screens: Self.screens, ownPID: 1) == ["EXT"])
    }
}
