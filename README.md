# Halo

A native SwiftUI disk-space visualizer for macOS. Halo scans a directory tree,
classifies what's using space, and renders it as an interactive donut — with two
lenses (**by folder** and **by type**) and a synced breakdown sidebar that
surfaces reclaimable developer junk (`node_modules`, caches, build output,
`.Trash`, …).

It's built on **DiskKit**, a small library that does a fast, parallel POSIX
filesystem walk and builds a classified directory tree.

## Requirements

- macOS 26 or newer
- Swift 6.2+ toolchain (ships with Xcode 26)

The package builds in Swift 6 language mode with strict data-race checking, and
uses the standard-library [`Synchronization`](https://developer.apple.com/documentation/synchronization)
module (`Mutex`).

## Build & run

A `Makefile` drives everything (run `make` to list targets):

```sh
make run     # build & launch from source
make app     # -> Halo.app  (double-clickable, ad-hoc signed)
make dmg     # -> Halo.dmg  (drag-to-install disk image)
make icon    # regenerate Icons/AppIcon.icns from the Swift generator
make test    # run the test suite
```

`make app` wraps the release binary in a `.app` via the `bundle-app` package
plugin (Info.plist + icon + ad-hoc signature). CI builds and uploads `Halo.dmg`
as an artifact on every push and PR.

## How it works

- **Parallel scan.** `DiskKit.TreeScanner` walks the tree with raw POSIX calls
  (`opendir` / `readdir` / `lstat`) across a pool of workers pulling from a
  shared, depth-first work-stealing queue, so one huge subtree can't bottleneck
  the scan. Sizes are disk usage (allocated blocks); symlinks aren't followed.
- **Classification.** Each directory and file is bucketed into a `FileCategory`
  (dependencies, caches, build output, media, code, …), and known-regenerable
  directories (`node_modules`, `Caches`, `DerivedData`, `.Trash`, …) are flagged
  reclaimable.
- **Two lenses.** "By folder" shows the immediate children of the current
  directory; "by type" rolls every leaf up by category. Both render as donut
  slices kept in sync with the sidebar.
- **Streaming.** The app paints the ring immediately and fills in each top-level
  subtree as it finishes, with a live file/byte counter throughout the scan.

See [docs/halo.md](docs/halo.md) for the full architecture.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/Halo/` | SwiftUI app: donut view, breakdown sidebar, scan model. |
| `Sources/DiskKit/` | Scan library: parallel walk, classified tree, derivations, formatting. |
| `Tests/` | DiskKit + Halo unit tests. |
| `Plugins/BundleApp/` | `swift package bundle-app` — wraps a release binary into a `.app`. |
| `Makefile` · `Icons/` | Build/package targets and the Swift app-icon generator. |

## Development

```sh
swift build      # build
swift test       # run the test suite
```
