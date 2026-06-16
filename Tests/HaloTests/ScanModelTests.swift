import XCTest

@testable import DiskKit
@testable import Halo

@MainActor
final class ScanModelTests: XCTestCase {

    /// Hovering a slice must report that segment's real size in the hole.
    /// Reproduces the "hover shows 0 KB" report against a fully-sized tree.
    func testHoverFocusReportsSegmentSize() {
        let model = ScanModel()
        model.load(MockTree.make())

        let segs = model.segments
        XCTAssertFalse(segs.isEmpty, "mock tree should produce folder segments")

        let biggest = segs.max { $0.size < $1.size }!
        XCTAssertGreaterThan(biggest.size, 0)

        model.hover = biggest.id
        XCTAssertEqual(model.focus?.id, biggest.id, "focus resolves the hovered id")
        XCTAssertEqual(model.focus?.size, biggest.size, "focus reports the segment's size")
        XCTAssertGreaterThan(model.focus?.size ?? 0, 0, "hover must not show 0")
    }

    /// Every folder segment must round-trip through hover with its own size.
    func testEveryFolderSegmentFocusesToItsSize() {
        let model = ScanModel()
        model.load(MockTree.make())
        for seg in model.segments {
            model.hover = seg.id
            XCTAssertEqual(model.focus?.size, seg.size, "segment \(seg.label) focus size")
        }
    }

    /// A zero-size child — a not-yet-sized streaming placeholder, or a genuinely
    /// empty directory — must not appear as a segment, so it cannot be hovered
    /// to show a meaningless "0 KB". This reproduces the reported bug where
    /// hovering `.swiftpm` (still a placeholder mid-scan) showed 0.
    func testZeroSizeChildrenAreNotSegments() {
        let GB: Int64 = 1_073_741_824
        let placeholder = DirNode(
            name: ".swiftpm", category: .other,
            isReclaimable: false, fileBytes: [:], children: [])
        let real = DirNode(
            name: "Movies", category: .media,
            isReclaimable: false, fileBytes: [.media: 10 * GB], children: [])
        let root = DirNode(
            name: "alex", category: .other,
            isReclaimable: false, fileBytes: [:], children: [placeholder, real])

        let model = ScanModel()
        model.load(root)

        XCTAssertNil(
            model.segments.first { $0.size == 0 },
            "no zero-size segments should be produced")
        XCTAssertFalse(
            model.segments.contains { $0.label == ".swiftpm" },
            "an unsized placeholder must not be shown")
        XCTAssertTrue(model.segments.contains { $0.label == "Movies" })
        XCTAssertTrue(
            model.arcs.allSatisfy { $0.seg.size > 0 },
            "no zero-size arcs to hover")
    }

    /// Subtrees that finish while the user is drilled into another one must
    /// still make it into the root: `applyChild` deliberately skips restitching
    /// mid-drill, so `finishScan` must always rebuild the root — keeping the
    /// user's scope — or navigating back would show stale placeholders.
    func testScanFinishRestitchesRootWhileUserIsDrilledIn() {
        let model = ScanModel()
        let pa = DirNode(
            name: "a", category: .other, isReclaimable: false,
            fileBytes: [:], children: [])
        let pb = DirNode(
            name: "b", category: .other, isReclaimable: false,
            fileBytes: [:], children: [])
        model.installRoot(
            DirNode(
                name: "alex", category: .other, isReclaimable: false,
                fileBytes: [:], children: [pa, pb]))

        // Subtree "a" finishes; the user drills into it while "b" is still walking.
        model.applyChild(
            0,
            DirNode(
                name: "a", category: .other, isReclaimable: false,
                fileBytes: [.other: 1_000], children: []))
        model.jump(to: model.root!.children.first { $0.name == "a" }!)

        // Subtree "b" finishes while drilled in (no restitch), then the scan ends.
        model.applyChild(
            1,
            DirNode(
                name: "b", category: .media, isReclaimable: false,
                fileBytes: [.media: 2_000], children: []))
        model.finishScan()

        XCTAssertEqual(model.current?.name, "a", "the user's scope is preserved")
        model.back()
        XCTAssertEqual(
            model.current?.size, 3_000,
            "the root includes the subtree that finished mid-drill")
        XCTAssertTrue(
            model.root!.children.contains { $0.name == "b" && $0.size == 2_000 },
            "navigating back shows the completed subtree, not a placeholder")
    }

    /// Hovering a point in the donut must resolve to the arc actually under the
    /// cursor. Reproduces "hovering the biggest section showed the smallest":
    /// the old per-slice `.onHover` let the topmost (smallest) slice's full-frame
    /// tracking area swallow every hover.
    func testDonutHoverHitsTheArcUnderTheCursor() {
        let model = ScanModel()
        model.load(MockTree.make())
        let arcs = model.arcs
        XCTAssertFalse(arcs.isEmpty)

        let center: CGFloat = 230
        let r0: CGFloat = 122
        let r1: CGFloat = 196
        let rMid = (r0 + r1) / 2

        func point(atAngle a: Double) -> CGPoint {
            CGPoint(x: center + rMid * CGFloat(cos(a)), y: center + rMid * CGFloat(sin(a)))
        }

        for arc in arcs {
            let p = point(atAngle: (arc.a0 + arc.a1) / 2)
            XCTAssertEqual(
                hitTestArc(at: p, in: arcs, center: center, r0: r0, r1: r1),
                arc.seg.id, "midpoint of \(arc.seg.label) must hit its own arc")
        }

        // The specific reported failure: the largest slice resolves to itself.
        let biggest = arcs.max { $0.seg.size < $1.seg.size }!
        let smallest = arcs.min { $0.seg.size < $1.seg.size }!
        let hit = hitTestArc(
            at: point(atAngle: (biggest.a0 + biggest.a1) / 2),
            in: arcs, center: center, r0: r0, r1: r1)
        XCTAssertEqual(hit, biggest.seg.id)
        XCTAssertNotEqual(hit, smallest.seg.id, "biggest must not resolve to smallest")

        // Inside the hole and outside the ring resolve to nothing.
        XCTAssertNil(
            hitTestArc(
                at: CGPoint(x: center, y: center),
                in: arcs, center: center, r0: r0, r1: r1))
        XCTAssertNil(
            hitTestArc(
                at: CGPoint(x: center + 400, y: center),
                in: arcs, center: center, r0: r0, r1: r1))
    }

    private static let GB: Int64 = 1_073_741_824

    /// Tapping a folder that holds only files (no subdirectories) must still
    /// drill into it. Reproduces "the breadcrumb doesn't work" — `tapSegment`
    /// used to ignore any folder whose `children` were empty, so clicking a
    /// leaf folder did nothing.
    func testTappingLeafFolderDrillsIntoIt() {
        let leaf = DirNode(
            name: "Caches", category: .cache,
            isReclaimable: true, fileBytes: [.cache: 5 * Self.GB], children: [])
        let root = DirNode(
            name: "alex", category: .other,
            isReclaimable: false, fileBytes: [:], children: [leaf])
        let model = ScanModel()
        model.load(root)

        let seg = model.segments.first { $0.label == "Caches" }!
        model.tapSegment(seg)

        XCTAssertEqual(model.current?.name, "Caches", "tapping a leaf folder drills into it")
        XCTAssertEqual(model.path.count, 2)
    }

    /// Segment ids must be derived from the node's *path*, not its object
    /// identity: every streaming restitch rebuilds the tree with fresh nodes,
    /// and an identity-based id silently invalidated the hovered slice mid-scan.
    func testSegmentIDsAreStableAcrossTreeRebuilds() {
        func makeTree() -> DirNode {
            let nm = DirNode(
                name: "node_modules", category: .deps,
                isReclaimable: true, fileBytes: [.deps: 2 * Self.GB], children: [])
            let app = DirNode(
                name: "app", category: .other,
                isReclaimable: false, fileBytes: [.code: 1 * Self.GB], children: [nm])
            return DirNode(
                name: "alex", category: .other,
                isReclaimable: false, fileBytes: [:], children: [app])
        }

        let model = ScanModel()
        model.load(makeTree())
        let before = model.segments.map(\.id)

        model.load(makeTree())  // structurally identical, all-new objects
        XCTAssertEqual(
            model.segments.map(\.id), before,
            "ids survive a rebuild of the same tree")
    }

    /// `jump(to:)` must land on the requested directory, not bounce up to its
    /// parent when that directory has no subdirectories. Reproduces "clicking a
    /// dir goes to the parent instead".
    func testJumpToLeafDirLandsOnIt() {
        let leaf = DirNode(
            name: "com.apple.wallpaper.caches", category: .cache,
            isReclaimable: true, fileBytes: [.cache: 200 * Self.GB], children: [])
        let mid = DirNode(
            name: "Caches", category: .cache,
            isReclaimable: true, fileBytes: [:], children: [leaf])
        let root = DirNode(
            name: "alex", category: .other,
            isReclaimable: false, fileBytes: [:], children: [mid])
        let model = ScanModel()
        model.load(root)

        model.jump(to: leaf)
        XCTAssertEqual(
            model.current?.name, "com.apple.wallpaper.caches",
            "jump lands on the leaf, not its parent")
    }

    // MARK: - Summary facts

    /// The AI summary's prompt must describe the *current* scope using only the
    /// figures the rail already shows, so the model can never reference a number
    /// the user can't see. We test the fact-builder (pure, deterministic), not
    /// the on-device model (which can't run headlessly).
    func testSummaryFactsDescribeFolderScope() {
        let model = ScanModel()
        model.load(MockTree.make())
        let facts = model.summaryFacts()

        XCTAssertTrue(facts.contains("Folder: ~"), "names the scanned root")
        XCTAssertTrue(facts.contains("Total size:"), "states the total")
        XCTAssertTrue(facts.contains("Largest items inside"), "folder-lens framing")
        XCTAssertTrue(facts.contains("Reclaimable in total"), "states reclaimable total")
        // Every line's figure must be one the rail also renders for a segment.
        for seg in model.segments.prefix(8) {
            XCTAssertTrue(
                facts.contains(seg.label), "facts mention the \(seg.label) segment")
        }
    }

    /// The reclaim advice must rank by *reclaimable* bytes, not total size, so the
    /// model recommends the biggest cleanup win rather than the largest folder.
    /// In the mock tree the largest folder (Docker, ~63 GB) has only ~9 GB
    /// reclaimable, while Library (~27 GB reclaimable) is the real opportunity.
    func testSummaryFactsRankReclaimByReclaimableNotSize() {
        let model = ScanModel()
        model.load(MockTree.make())
        let facts = model.summaryFacts()

        guard let header = facts.range(of: "Biggest cleanup opportunities") else {
            return XCTFail("facts should list ranked cleanup opportunities")
        }
        let ranked = String(facts[header.upperBound...])
        guard let libIdx = ranked.range(of: "Library"),
            let dockerIdx = ranked.range(of: "Docker")
        else { return XCTFail("ranked list should mention both Library and Docker") }
        XCTAssertTrue(
            libIdx.lowerBound < dockerIdx.lowerBound,
            "Library (more reclaimable) must rank above Docker (larger folder)")

        // The largest folder by total size is Docker, but it must not lead the
        // cleanup ranking — that's the bug being guarded against.
        let firstBullet = ranked.split(separator: "-").dropFirst().first.map(String.init) ?? ""
        XCTAssertFalse(
            firstBullet.contains("Docker"),
            "the largest folder must not be the top cleanup recommendation")
    }

    /// The facts must tell the model which reclaimable space is high-confidence
    /// (safe to clear) versus what needs review, and must precompute the totals so
    /// the model never has to add figures itself (it was naming two items but
    /// quoting one's number). Build a folder mixing a high- and a medium-confidence
    /// reclaim root so both tiers appear.
    func testSummaryFactsCarryConfidenceAndPrecomputedTotals() {
        let GB = Self.GB
        let derived = DirNode(
            name: "DerivedData", category: .build,
            reclaim: ReclaimMark(confidence: .high, signal: .knownName, reason: "build output"),
            fileBytes: [.build: 10 * GB], children: [])
        let cache = DirNode(
            name: "SomeCache", category: .cache,
            reclaim: ReclaimMark(confidence: .medium, signal: .knownName, reason: "cache"),
            fileBytes: [.cache: 4 * GB], children: [])
        let dev = DirNode(
            name: "Developer", category: .build, reclaim: nil,
            fileBytes: [:], children: [derived, cache])
        let root = DirNode(
            name: "home", category: .other, reclaim: nil, fileBytes: [:], children: [dev])

        let model = ScanModel()
        model.load(root)
        let facts = model.summaryFacts()

        XCTAssertTrue(
            facts.contains("safe to clear right away (high confidence): 10"),
            "precomputes the high-confidence total so the model needn't add")
        // The Developer opportunity mixes both tiers, so its line names both. Scope
        // to the cleanup-opportunities section so we don't match the size breakdown.
        guard let header = facts.range(of: "Biggest cleanup opportunities") else {
            return XCTFail("facts should list ranked cleanup opportunities")
        }
        guard
            let line = facts[header.upperBound...].split(separator: "\n").first(where: {
                $0.contains("Developer:")
            })
        else { return XCTFail("expected a Developer cleanup line") }
        XCTAssertTrue(line.contains("safe to clear"), "names the high-confidence portion")
        XCTAssertTrue(line.contains("to review first"), "flags the medium-confidence portion")
        XCTAssertTrue(
            facts.contains("never add them"),
            "instructs the model not to sum figures")
    }

    /// Switching to the type lens reframes the facts as a per-type breakdown.
    func testSummaryFactsFollowTheActiveLens() {
        let model = ScanModel()
        model.load(MockTree.make())
        model.setMode(.type)
        let facts = model.summaryFacts()

        XCTAssertTrue(facts.contains("Breakdown by file type"), "type-lens framing")
        XCTAssertFalse(facts.contains("Largest items inside"), "not the folder framing")
    }

    /// Drilling into a subfolder re-frames the facts around that folder, so the
    /// auto-generated overview always describes the scope the user is looking at.
    func testSummaryFactsFollowNavigation() {
        let model = ScanModel()
        model.load(MockTree.make())

        guard let projects = model.current?.children.first(where: { $0.name == "Projects" })
        else { return XCTFail("mock tree should contain a Projects folder") }
        model.jump(to: projects)

        let facts = model.summaryFacts()
        XCTAssertTrue(facts.contains("Folder: Projects"), "facts name the drilled-into folder")
        XCTAssertTrue(
            facts.contains("acme-dashboard"), "facts list the children of the new scope")
    }
}
