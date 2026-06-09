import Foundation

/// Rule-based classification of directories and files into `FileCategory`s,
/// distilled from the design's intent: surface developer junk (`node_modules`,
/// caches, build output, Docker, stale checkpoints) as first-class concepts.
public enum Classifier {

    /// How a directory is categorized.
    public struct DirKind {
        public let category: FileCategory
        /// The directory as a whole is safe-ish to delete and regenerates.
        public let reclaimable: Bool
        /// Everything beneath this directory should be attributed to
        /// `category` regardless of file extension (e.g. all files under
        /// `node_modules` are "Dependencies", all under `Caches` are "Caches").
        public let overridesChildren: Bool
    }

    /// Classify a directory by its (lowercased) name.
    public static func classifyDir(_ name: String) -> DirKind {
        let n = name.lowercased()
        switch n {
        case "node_modules", ".venv", "venv", "pods", "vendor", ".cargo", "site-packages":
            return DirKind(category: .deps, reclaimable: true, overridesChildren: true)
        case "caches", "cache", ".cache", "wandb":
            return DirKind(category: .cache, reclaimable: true, overridesChildren: true)
        case "deriveddata", ".next", "dist", "build", ".build", "target", "out", ".turbo":
            return DirKind(category: .build, reclaimable: true, overridesChildren: true)
        case ".trash":
            return DirKind(category: .trash, reclaimable: true, overridesChildren: true)
        case "containers", "docker":
            return DirKind(category: .container, reclaimable: false, overridesChildren: true)
        case "movies", "music", "pictures", "photos":
            return DirKind(category: .media, reclaimable: false, overridesChildren: true)
        case "documents", "notes":
            return DirKind(category: .docs, reclaimable: false, overridesChildren: false)
        case "applications":
            return DirKind(category: .app, reclaimable: false, overridesChildren: true)
        case "library", "application support":
            return DirKind(category: .other, reclaimable: false, overridesChildren: false)
        case "projects", "developer", "code", "src", "repos", ".git":
            return DirKind(category: .code, reclaimable: false, overridesChildren: false)
        default:
            return DirKind(category: .other, reclaimable: false, overridesChildren: false)
        }
    }

    /// Classify a file by its (lowercased, no-dot) extension.
    public static func classifyFile(ext: String) -> FileCategory {
        switch ext {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm",
             "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "raw", "psd",
             "mp3", "wav", "flac", "aac", "m4a", "aiff":
            return .media
        case "swift", "ts", "tsx", "js", "jsx", "mjs", "py", "rs", "go", "rb", "php",
             "c", "cc", "cpp", "h", "hpp", "java", "kt", "cs", "scala", "sh", "lua",
             "html", "css", "scss", "json", "yaml", "yml", "toml", "xml", "sql":
            return .code
        case "pdf", "doc", "docx", "pages", "txt", "md", "rtf", "key", "numbers",
             "xls", "xlsx", "ppt", "pptx", "csv", "epub", "tex":
            return .docs
        case "app":
            return .app
        default:
            return .other
        }
    }
}
