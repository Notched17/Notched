// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import Notched

/// Apple's expanded-region algorithm (ISLAND-BEHAVIOR.md §4): center first,
/// leading and trailing share the rest, priority goes full width,
/// `.belowIfTooWide` drops leading below the camera housing.
@Suite("ExpandedRegionsGeometry")
struct ExpandedRegionsGeometryTests {
    typealias Region = ExpandedRegionsGeometry.Region

    /// This Mac: a 488 pt island with 30 pt insets, around a 208 pt notch
    /// (plus 8 pt gaps) that is 38 pt tall.
    let geometry = ExpandedRegionsGeometry(width: 428, housing: CGSize(width: 224, height: 38), spacing: 8)

    /// Records the widths a region was offered.
    final class Offers { var widths: [CGFloat] = [] }

    /// A region with a fixed natural size that shrinks to fit.
    private func fixed(_ role: ExpandedRegionsGeometry.Role, _ size: CGSize, minWidth: CGFloat = 0,
                       priority: Double = 0, belowIfTooWide: Bool = false, offers: Offers? = nil) -> Region {
        Region(role: role, priority: priority, belowIfTooWide: belowIfTooWide, minWidth: minWidth) { width in
            offers?.widths.append(width)
            return CGSize(width: min(size.width, width), height: size.height)
        }
    }

    @Test("The center is sized first, leaving leading and trailing their minimum widths")
    func centerSizedFirst() {
        let result = geometry.place([
            fixed(.leading, CGSize(width: 60, height: 20), minWidth: 40),
            fixed(.trailing, CGSize(width: 60, height: 20), minWidth: 40),
            fixed(.center, CGSize(width: 1_000, height: 30)),
        ])
        let center = result.frames[.center]
        #expect(center?.width == 332)
        #expect(center?.minX == 48)
        #expect(center?.minY == 38)
    }

    @Test("Leading and trailing are offered the same width beside the housing")
    func sidesShareEqually() {
        let leadingOffers = Offers()
        let trailingOffers = Offers()
        let result = geometry.place([
            fixed(.leading, CGSize(width: 30, height: 20), offers: leadingOffers),
            fixed(.trailing, CGSize(width: 90, height: 20), offers: trailingOffers),
        ])
        #expect(leadingOffers.widths.last == 102)
        #expect(trailingOffers.widths.last == 102)
        #expect(result.frames[.leading]?.minX == 0)
        #expect(result.frames[.trailing]?.maxX == 428)
    }

    @Test("Side regions shorter than the housing row are centred in it, beside the camera")
    func shortSidesCentredInHousingRow() {
        let result = geometry.place([fixed(.leading, CGSize(width: 30, height: 20))])
        #expect(result.frames[.leading]?.minY == 9)
    }

    @Test("A side region taller than the housing row narrows to sit beside the center")
    func tallSideNarrowsBesideCenter() {
        let result = geometry.place([
            fixed(.leading, CGSize(width: 90, height: 80)),
            fixed(.center, CGSize(width: 300, height: 30)),
        ])
        #expect(result.frames[.leading]?.width == 56)
        #expect(result.frames[.leading]?.minY == 0)
    }

    @Test("The highest-priority region renders at the full width")
    func priorityFullWidth() {
        let result = geometry.place([
            fixed(.leading, CGSize(width: 40, height: 20)),
            fixed(.center, CGSize(width: 1_000, height: 30), priority: 1),
        ])
        #expect(result.frames[.center]?.minX == 0)
        #expect(result.frames[.center]?.width == 428)
    }

    @Test("A leading region marked belowIfTooWide drops below the housing when it doesn't fit beside it")
    func belowIfTooWide() {
        let result = geometry.place([fixed(.leading, CGSize(width: 150, height: 20), belowIfTooWide: true)])
        #expect(result.frames[.leading]?.minY == 38)
        #expect(result.frames[.leading]?.width == 150)
    }

    @Test("The bottom region spans the full width below everything, and sets the height")
    func bottomSpansWidth() {
        let result = geometry.place([
            fixed(.leading, CGSize(width: 40, height: 20)),
            fixed(.center, CGSize(width: 200, height: 30)),
            fixed(.bottom, CGSize(width: 1_000, height: 24)),
        ])
        // Typed constants: an untyped sum here makes #expect implicitly unwrap a nil frame and crash.
        let bottomTop: CGFloat = 38 + 30 + 8
        let bottom = result.frames[.bottom]
        #expect(bottom?.minX == 0)
        #expect(bottom?.width == 428)
        #expect(bottom?.minY == bottomTop)
        #expect(result.size == CGSize(width: 428, height: bottomTop + 24))
    }

    @Test("Without a camera housing (the pill), center sits between leading and trailing at the top")
    func pillHasNoHousingRow() {
        let pill = ExpandedRegionsGeometry(width: 368, housing: .zero, spacing: 8)
        let result = pill.place([
            fixed(.leading, CGSize(width: 40, height: 20)),
            fixed(.trailing, CGSize(width: 40, height: 20)),
            fixed(.center, CGSize(width: 100, height: 30)),
        ])
        #expect(result.frames[.center]?.minY == 0)
        #expect(result.frames[.center]?.midX == 184)
    }

    @Test("With nothing beside the housing, the content still clears the housing row")
    func emptyStillClearsHousing() {
        let result = geometry.place([fixed(.center, CGSize(width: 100, height: 30))])
        #expect(result.frames[.center]?.minY == 38)
        #expect(result.size.height == 68)
    }
}
