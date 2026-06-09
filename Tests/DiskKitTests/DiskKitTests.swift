import XCTest
import Foundation
@testable import DiskKit

/// Thread-safe sink for the streaming scan's callbacks, which fire on scanner
/// threads. Reads are safe once `scanStreaming` (synchronous) has returned.
private final class StreamSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _root: DirNode?
    private var _children: [Int: DirNode] = [:]
    private var _doneCount = 0

    var root: DirNode? { lock.withLock { _root } }
    var children: [Int: DirNode] { lock.withLock { _children } }
    var doneCount: Int { lock.withLock { _doneCount } }

    func setRoot(_ n: DirNode) { lock.withLock { _root = n } }
    func addChild(_ i: Int, _ n: DirNode) { lock.withLock { _children[i] = n } }
    func finish() { lock.withLock { _doneCount += 1 } }
}

final class ClassifierTests: XCTestCase {
    func testReclaimableDirsOverrideChildren() {
        let nm = Classifier.classifyDir("node_modules")
        XCTAssertEqual(nm.category, .deps)
        XCTAssertTrue(nm.reclaimable)
        XCTAssertTrue(nm.overridesChildren)

        let caches = Classifier.classifyDir("Caches")
        XCTAssertEqual(caches.category, .cache)
        XCTAssertTrue(caches.reclaimable)

        let trash = Classifier.classifyDir(".Trash")
        XCTAssertEqual(trash.category, .trash)
        XCTAssertTrue(trash.reclaimable)
    }

    func testFileExtensionCategories() {
        XCTAssertEqual(Classifier.classifyFile(ext: "mp4"), .media)
        XCTAssertEqual(Classifier.classifyFile(ext: "swift"), .code)
        XCTAssertEqual(Classifier.classifyFile(ext: "pdf"), .docs)
        XCTAssertEqual(Classifier.classifyFile(ext: "xyz"), .other)
    }
}

final class DerivationsTests: XCTestCase {
    private let GB: Int64 = 1_073_741_824

    func testReclaimBytesCountsReclaimableSubtrees() {
        let root = MockTree.make()
        let recl = Derive.reclaimBytes(root)
        // node_modules (8+6) + .next (3) + dist (1) + .venv (4) + wandb (2)
        // + Caches (11) + DerivedData (16) + docker build cache (9) + .Trash (5)
        XCTAssertEqual(recl, (8 + 6 + 3 + 1 + 4 + 2 + 11 + 16 + 9 + 5) * GB)
    }

    func testTypeSizesSumToTotal() {
        let root = MockTree.make()
        let sizes = Derive.typeSizes(root)
        XCTAssertEqual(sizes.values.reduce(0, +), root.size,
                       "every leaf byte is attributed to exactly one category")
    }

    func testDepsAggregatedAcrossProjects() {
        let root = MockTree.make()
        let sizes = Derive.typeSizes(root)
        // node_modules (8 + 6) + .venv (4) all roll up to deps.
        XCTAssertEqual(sizes[.deps], (8 + 6 + 4) * GB)
    }

    func testTypeLocationsFindsEveryNodeModules() {
        let root = MockTree.make()
        let locs = Derive.typeLocations(root, .deps)
        let names = Set(locs.map { $0.node.name })
        XCTAssertTrue(names.contains("node_modules"))
        XCTAssertTrue(names.contains(".venv"))
        // sorted descending by size
        let sizes = locs.map { $0.size }
        XCTAssertEqual(sizes, sizes.sorted(by: >))
    }

    func testPathToRoot() {
        let root = MockTree.make()
        let library = root.children.first { $0.name == "Library" }!
        let caches = library.children.first { $0.name == "Caches" }!
        let path = Derive.pathTo(caches).map { $0.name }
        XCTAssertEqual(path, ["alex", "Library", "Caches"])
    }
}

final class TreeScannerTests: XCTestCase {
    func testScansRealTempTree() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskkit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try Data(count: 20_000).write(to: base.appendingPathComponent("node_modules/dep.bin"))
        try Data(count: 8_000).write(to: base.appendingPathComponent("readme.md"))
        defer { try? FileManager.default.removeItem(at: base) }

        let root = TreeScanner.scan(base.path)
        XCTAssertGreaterThan(root.size, 0)

        let nm = root.children.first { $0.name == "node_modules" }
        XCTAssertNotNil(nm)
        XCTAssertEqual(nm?.category, .deps)
        XCTAssertEqual(nm?.isReclaimable, true)

        // The .md file in the root is categorized as docs by extension.
        let sizes = Derive.typeSizes(root)
        XCTAssertNotNil(sizes[.docs])
        XCTAssertNotNil(sizes[.deps])
    }

    func testFormatSize() {
        XCTAssertEqual(formatSize(0), "0 KB")
        XCTAssertEqual(formatSize(2 * 1_073_741_824), "2.0 GB")
        XCTAssertTrue(formatSize(5 * 1_048_576).hasSuffix("MB"))
    }

    /// The streaming scan must report every top-level subtree exactly once and,
    /// once reassembled, match the blocking scan byte-for-byte. This exercises
    /// the shared work-stealing queue and the per-subtree completion tracker.
    func testStreamingMatchesBlockingScan() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskkit-stream-\(UUID().uuidString)")
        let fm = FileManager.default
        // A deliberately lopsided tree: nested dirs, an override dir, an empty
        // dir, and a loose top-level file (which belongs to the root, not a
        // subtree).
        try fm.createDirectory(at: base.appendingPathComponent("alpha/sub/deep"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("beta/node_modules"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("gamma"),
                               withIntermediateDirectories: true)
        try Data(count: 30_000).write(to: base.appendingPathComponent("alpha/sub/deep/a.bin"))
        try Data(count: 10_000).write(to: base.appendingPathComponent("alpha/b.bin"))
        try Data(count: 50_000).write(to: base.appendingPathComponent("beta/node_modules/dep.bin"))
        try Data(count: 5_000).write(to: base.appendingPathComponent("loose.md"))
        defer { try? fm.removeItem(at: base) }

        let blocking = TreeScanner.scan(base.path)

        // Collect the streamed pieces (callbacks fire on scanner threads). The
        // scan is synchronous, so everything is in by the time it returns.
        let sink = StreamSink()
        TreeScanner.scanStreaming(
            base.path, progress: ScanProgress(),
            onRoot:  { node in sink.setRoot(node) },
            onChild: { i, node in sink.addChild(i, node) },
            onDone:  { sink.finish() }
        )

        let rootNode = try XCTUnwrap(sink.root)
        let placeholders = rootNode.children
        XCTAssertEqual(sink.doneCount, 1, "onDone fires exactly once")
        XCTAssertEqual(placeholders.count, blocking.children.count,
                       "one placeholder per top-level directory")
        XCTAssertEqual(Set(sink.children.keys), Set(0..<placeholders.count),
                       "every top-level subtree reported exactly once, no gaps or repeats")

        // Reassemble in placeholder order and compare to the blocking scan.
        let ordered = (0..<placeholders.count).map { sink.children[$0]! }
        let streamed = DirNode(name: rootNode.name, category: rootNode.category,
                               isReclaimable: rootNode.isReclaimable,
                               fileBytes: rootNode.fileBytes, children: ordered)
        XCTAssertEqual(streamed.size, blocking.size,
                       "streamed tree totals the same as the blocking scan")

        // Per-subtree sizes line up by name (order may differ between the two).
        let streamedByName = Dictionary(uniqueKeysWithValues: streamed.children.map { ($0.name, $0.size) })
        for c in blocking.children {
            XCTAssertEqual(streamedByName[c.name], c.size, "subtree \(c.name) sizes match")
        }
        // The override dir's contents roll up to .deps in both.
        XCTAssertEqual(Derive.typeSizes(streamed)[.deps], Derive.typeSizes(blocking)[.deps])
    }
}
