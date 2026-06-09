import Foundation
import Synchronization
#if canImport(Darwin)
import Darwin
#endif

/// Builds a classified `DirNode` tree from a real filesystem path using raw
/// POSIX directory calls. Symlinks are not followed; unreadable directories are
/// skipped. Sizes are disk usage (allocated blocks).
///
/// Parallelism mirrors duaswift's `DiskScanner`: instead of the old
/// "one thread per top-level directory, each subtree walked serially" scheme
/// (which left every core but one idle whenever a single subtree — `~/Library`,
/// a giant `node_modules` — dominated), all worker threads pull directories
/// from a shared work-stealing `NodeQueue`. Load stays balanced regardless of
/// tree shape, so a lopsided home folder no longer bottlenecks the scan.
public enum TreeScanner {

    /// Blocking, build-the-whole-tree scan. Convenient for tests; the GUI uses
    /// `scanStreaming` so it can render before a large scan finishes.
    public static func scan(_ rootPath: String, progress: ScanProgress = ScanProgress()) -> DirNode {
        let rootName = (rootPath as NSString).lastPathComponent
        let root = BuildNode(name: rootName, path: rootPath, inherited: nil)
        drain(NodeQueue([root]), progress: progress)
        return freeze(root)
    }

    /// Streaming scan for the UI. Reports the root with **placeholder** (size 0)
    /// children immediately, then builds the whole tree with a shared pool of
    /// workers and reports each top-level subtree via `onChild` the moment it —
    /// and everything beneath it — is finished, in any order. `progress` ticks
    /// the whole time so the caller can show a live counter. All callbacks fire
    /// on scanner threads — the caller is responsible for hopping to the main
    /// actor.
    public static func scanStreaming(
        _ rootPath: String,
        progress: ScanProgress,
        onRoot: @Sendable (DirNode) -> Void,
        onChild: @Sendable (Int, DirNode) -> Void,
        onDone: @Sendable () -> Void
    ) {
        let rootName = (rootPath as NSString).lastPathComponent
        let root = BuildNode(name: rootName, path: rootPath, inherited: nil)
        // List the root directory synchronously so we can paint placeholders for
        // every top-level subtree before the heavy walk begins.
        list(root, progress: progress)

        let tops = root.children
        for (i, t) in tops.enumerated() { t.rootIndex = i }

        let placeholders = tops.map { t in
            DirNode(name: t.name, category: t.category,
                    isReclaimable: t.reclaimable, fileBytes: [:], children: [])
        }
        onRoot(DirNode(name: root.name, category: root.category,
                       isReclaimable: root.reclaimable,
                       fileBytes: root.fileBytes, children: placeholders))

        guard !tops.isEmpty else { onDone(); return }

        // One pending counter per top-level subtree: when it hits zero, every
        // node under that subtree is finished, so we can freeze and report it.
        // `onChild` is reported synchronously from within `concurrentPerform`,
        // so it never outlives this call — `withoutActuallyEscaping` lets the
        // tracker hold it without forcing the public API to be `@escaping`.
        withoutActuallyEscaping(onChild) { onChild in
            let tracker = SubtreeTracker(count: tops.count) { i in onChild(i, freeze(tops[i])) }
            for t in tops { tracker.enter(t.rootIndex) }   // the top node itself

            let queue = NodeQueue(tops)
            DispatchQueue.concurrentPerform(iterations: workerCount) { _ in
                while let node = queue.pop() {
                    list(node, progress: progress)
                    let idx = node.rootIndex
                    for c in node.children { c.rootIndex = idx }
                    tracker.enter(idx, count: node.children.count)  // children, before…
                    queue.push(node.children)
                    queue.finishOne()
                    tracker.leave(idx)                              // …finishing this node
                }
            }
        }
        onDone()
    }

    private static var workerCount: Int {
        max(1, ProcessInfo.processInfo.activeProcessorCount)
    }

    /// Runs every node in `queue` through `list` using the shared worker pool.
    private static func drain(_ queue: NodeQueue, progress: ScanProgress) {
        DispatchQueue.concurrentPerform(iterations: workerCount) { _ in
            while let node = queue.pop() {
                list(node, progress: progress)
                queue.push(node.children)
                queue.finishOne()
            }
        }
    }

    // MARK: - Per-directory work

    /// Lists one directory: buckets its files into `node.fileBytes` and creates
    /// a `BuildNode` for each sub-directory (pushed onto the queue by the
    /// caller). Called exactly once per node, by the single worker that pops it,
    /// so the writes to `node` need no lock.
    private static func list(_ node: BuildNode, progress: ScanProgress) {
        guard let dirp = opendir(node.path) else { return }
        defer { closedir(dirp) }
        var fileBytes: [FileCategory: Int64] = [:]
        var children: [BuildNode] = []
        var fileCount = 0
        var byteSum: Int64 = 0
        while let entp = readdir(dirp) {
            let name = direntName(entp)
            if name == "." || name == ".." { continue }
            let full = node.path + "/" + name
            var st = stat()
            if full.withCString({ lstat($0, &st) }) != 0 { continue }
            let fmt = UInt32(st.st_mode) & UInt32(S_IFMT)
            if fmt == UInt32(S_IFDIR) {
                children.append(BuildNode(name: name, path: full, inherited: node.filesAs))
            } else if fmt == UInt32(S_IFREG) {
                let bytes = Int64(st.st_blocks) * 512
                let cat = node.filesAs ?? Classifier.classifyFile(ext: fileExt(name))
                fileBytes[cat, default: 0] += bytes
                fileCount += 1
                byteSum += bytes
            }
        }
        node.fileBytes = fileBytes
        node.children = children
        progress.add(files: fileCount, bytes: byteSum)
    }

    /// Converts the fully-built mutable tree into the immutable `DirNode` tree,
    /// computing subtree sizes and wiring parents bottom-up via `DirNode.init`.
    private static func freeze(_ b: BuildNode) -> DirNode {
        DirNode(name: b.name, category: b.category, isReclaimable: b.reclaimable,
                fileBytes: b.fileBytes, children: b.children.map(freeze))
    }

    private static func fileExt(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    @inline(__always)
    private static func direntName(_ entp: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: &entp.pointee.d_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(entp.pointee.d_namlen) + 1) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - Mutable build tree

/// A directory under construction. Becomes an immutable `DirNode` once the scan
/// finishes (`TreeScanner.freeze`).
///
/// `@unchecked Sendable` is safe because each node is *processed by exactly one
/// worker* (it is popped from the queue once), and that worker is the only
/// writer of `fileBytes`/`children`. Cross-thread visibility of those writes is
/// established by the `NodeQueue`/`SubtreeTracker` locks before any other thread
/// (or the final `freeze`) reads them.
private final class BuildNode: @unchecked Sendable {
    let name: String
    let path: String
    let category: FileCategory
    let reclaimable: Bool
    /// Override category applied to this node's own files and inherited by every
    /// descendant (e.g. everything under `node_modules` is "Dependencies").
    let filesAs: FileCategory?
    var fileBytes: [FileCategory: Int64] = [:]
    var children: [BuildNode] = []
    /// Index of the top-level subtree this node belongs to (streaming only).
    var rootIndex = 0

    init(name: String, path: String, inherited: FileCategory?) {
        self.name = name
        self.path = path
        let kind = Classifier.classifyDir(name)
        self.filesAs = inherited ?? (kind.overridesChildren ? kind.category : nil)
        self.category = inherited ?? kind.category
        self.reclaimable = inherited == nil ? kind.reclaimable : false
    }
}

/// Shared work-stealing stack of directory nodes still to be listed — the same
/// design as duaswift's `DirectoryQueue`, but carrying `BuildNode`s so workers
/// fill the tree as they go instead of only summing. `pending` counts nodes
/// enqueued-but-not-yet-finished so idle workers know when the scan is done.
/// `@unchecked Sendable`: the `NSCondition` serializes every access to `stack`
/// and `pending`. Pops are LIFO, so traversal is depth-first.
private final class NodeQueue: @unchecked Sendable {
    private let cond = NSCondition()
    private var stack: [BuildNode]
    private var pending: Int

    init(_ roots: [BuildNode]) {
        stack = roots
        pending = roots.count
    }

    /// Blocks until a node is available, or returns `nil` once the scan is
    /// finished (stack empty AND nothing pending). Wakes peers so they exit too.
    func pop() -> BuildNode? {
        cond.lock()
        defer { cond.unlock() }
        while stack.isEmpty && pending > 0 { cond.wait() }
        if stack.isEmpty {           // pending == 0 → everything is done
            cond.broadcast()         // wake the other idle workers to exit
            return nil
        }
        return stack.removeLast()
    }

    /// Adds discovered sub-directories and bumps the pending count.
    func push(_ nodes: [BuildNode]) {
        guard !nodes.isEmpty else { return }
        cond.lock()
        stack.append(contentsOf: nodes)
        pending += nodes.count
        cond.broadcast()
        cond.unlock()
    }

    /// Marks the node just listed as finished.
    func finishOne() {
        cond.lock()
        pending -= 1
        if pending == 0 { cond.broadcast() }
        cond.unlock()
    }
}

/// Per-top-level-subtree completion counter. Each subtree starts with its root
/// node pending; as nodes are discovered and finished the count rises and falls,
/// and the instant it returns to zero — meaning every node under that subtree is
/// done — `onFinish` fires with the subtree's index. Lets the streaming scan
/// report subtrees as they complete out of order across the shared worker pool.
private final class SubtreeTracker: @unchecked Sendable {
    private let counts: Mutex<[Int]>
    private let onFinish: @Sendable (Int) -> Void

    init(count: Int, onFinish: @escaping @Sendable (Int) -> Void) {
        self.counts = Mutex([Int](repeating: 0, count: count))
        self.onFinish = onFinish
    }

    func enter(_ i: Int, count n: Int = 1) {
        guard n > 0 else { return }
        counts.withLock { $0[i] += n }
    }

    func leave(_ i: Int) {
        let done = counts.withLock { c -> Bool in
            c[i] -= 1
            return c[i] == 0
        }
        if done { onFinish(i) }
    }
}
