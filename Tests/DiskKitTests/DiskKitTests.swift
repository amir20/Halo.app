import XCTest
import Foundation
@testable import DiskKit

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
}
