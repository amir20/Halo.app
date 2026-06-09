import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Builds a classified `DirNode` tree from a real filesystem path using raw
/// POSIX directory calls. Symlinks are not followed; unreadable directories are
/// skipped. Sizes are disk usage (allocated blocks).
public enum TreeScanner {

    /// Blocking, build-the-whole-tree scan. Convenient for tests; the GUI uses
    /// `scanStreaming` so it can render before a large scan finishes.
    public static func scan(_ rootPath: String, progress: ScanProgress = ScanProgress()) -> DirNode {
        let rootName = (rootPath as NSString).lastPathComponent
        let rootKind = Classifier.classifyDir(rootName)
        let filesAs = rootKind.overridesChildren ? rootKind.category : nil
        let entries = readEntries(rootPath, progress: progress)

        nonisolated(unsafe) var built = [DirNode?](repeating: nil, count: entries.dirs.count)
        if !entries.dirs.isEmpty {
            DispatchQueue.concurrentPerform(iterations: entries.dirs.count) { i in
                let d = entries.dirs[i]
                built[i] = buildNode(path: d.path, name: d.name, inherited: filesAs, progress: progress)
            }
        }
        return DirNode(name: rootName, category: rootKind.category,
                       isReclaimable: rootKind.reclaimable,
                       fileBytes: bucket(entries.files, as: filesAs),
                       children: built.compactMap { $0 })
    }

    /// Streaming scan for the UI. Reports the root with **placeholder** (size 0)
    /// children immediately, then builds each top-level subtree concurrently and
    /// reports each as it finishes. `progress` ticks the whole time so the
    /// caller can show a live counter. All callbacks fire on scanner threads —
    /// the caller is responsible for hopping to the main actor.
    public static func scanStreaming(
        _ rootPath: String,
        progress: ScanProgress,
        onRoot: @Sendable (DirNode) -> Void,
        onChild: @Sendable (Int, DirNode) -> Void,
        onDone: @Sendable () -> Void
    ) {
        let rootName = (rootPath as NSString).lastPathComponent
        let rootKind = Classifier.classifyDir(rootName)
        let filesAs = rootKind.overridesChildren ? rootKind.category : nil
        let entries = readEntries(rootPath, progress: progress)

        let placeholders = entries.dirs.map { d -> DirNode in
            let kind = Classifier.classifyDir(d.name)
            return DirNode(name: d.name, category: kind.category,
                           isReclaimable: kind.reclaimable, fileBytes: [:], children: [])
        }
        onRoot(DirNode(name: rootName, category: rootKind.category,
                       isReclaimable: rootKind.reclaimable,
                       fileBytes: bucket(entries.files, as: filesAs),
                       children: placeholders))

        let dirs = entries.dirs
        if !dirs.isEmpty {
            DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
                let node = buildNode(path: dirs[i].path, name: dirs[i].name,
                                     inherited: filesAs, progress: progress)
                onChild(i, node)
            }
        }
        onDone()
    }

    // MARK: - Recursive build

    private static func buildNode(path: String, name: String,
                                  inherited: FileCategory?, progress: ScanProgress) -> DirNode {
        let kind = Classifier.classifyDir(name)
        let filesAs = inherited ?? (kind.overridesChildren ? kind.category : nil)
        let entries = readEntries(path, progress: progress)

        var children: [DirNode] = []
        children.reserveCapacity(entries.dirs.count)
        for d in entries.dirs {
            children.append(buildNode(path: d.path, name: d.name, inherited: filesAs, progress: progress))
        }
        return DirNode(name: name,
                       category: inherited ?? kind.category,
                       isReclaimable: inherited == nil ? kind.reclaimable : false,
                       fileBytes: bucket(entries.files, as: filesAs),
                       children: children)
    }

    // MARK: - POSIX directory reading

    private static func readEntries(
        _ path: String, progress: ScanProgress
    ) -> (dirs: [(name: String, path: String)], files: [(ext: String, bytes: Int64)]) {
        guard let dirp = opendir(path) else { return ([], []) }
        defer { closedir(dirp) }
        var dirs: [(name: String, path: String)] = []
        var files: [(ext: String, bytes: Int64)] = []
        var fileBytes: Int64 = 0
        while let entp = readdir(dirp) {
            let name = direntName(entp)
            if name == "." || name == ".." { continue }
            let full = path + "/" + name
            var st = stat()
            if full.withCString({ lstat($0, &st) }) != 0 { continue }
            let fmt = UInt32(st.st_mode) & UInt32(S_IFMT)
            if fmt == UInt32(S_IFDIR) {
                dirs.append((name, full))
            } else if fmt == UInt32(S_IFREG) {
                let bytes = Int64(st.st_blocks) * 512
                files.append((fileExt(name), bytes))
                fileBytes += bytes
            }
        }
        progress.add(files: files.count, bytes: fileBytes)
        return (dirs, files)
    }

    private static func bucket(
        _ files: [(ext: String, bytes: Int64)], as override: FileCategory?
    ) -> [FileCategory: Int64] {
        var out: [FileCategory: Int64] = [:]
        for f in files {
            let cat = override ?? Classifier.classifyFile(ext: f.ext)
            out[cat, default: 0] += f.bytes
        }
        return out
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
