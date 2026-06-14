import DiskKit
import SwiftUI

/// The Finder-style right-click menu shared by the rail rows, the rail's
/// type-location rows, and the donut slices — so every place that shows a folder
/// offers the same actions in the same order (primary first, destructive last).
///
/// `node` is the real directory behind the row. It's `nil` for a row that maps
/// to no single folder — the "Files in this folder" pseudo-segment and the type
/// aggregates — which can only reveal the current scope, not act on one folder.
@ViewBuilder
func segmentMenuItems(for node: DirNode?, in model: ScanModel) -> some View {
    if let node {
        Button {
            model.jump(to: node)
        } label: {
            Label("Scan This Folder", systemImage: "magnifyingglass")
        }
        Button {
            model.revealInFinder(node)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        // An item already inside the Trash can't be re-trashed, so reclaiming it
        // is a permanent delete — the label has to say so rather than promise a
        // recoverable move. Both are destructive (rendered red).
        if node.category == .trash {
            Button(role: .destructive) {
                model.trash(node)
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
        } else {
            Button(role: .destructive) {
                model.trash(node)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    } else {
        Button {
            model.openInFinder()
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
    }
}
