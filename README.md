<div align="center">

<img src="docs/icon.png" width="120" alt="Halo">

# Halo

**A native macOS disk-space visualizer, written in SwiftUI.**

<img src="docs/screenshot.png" width="840" alt="Halo visualizing a folder as an interactive donut, with a synced breakdown sidebar and reclaimable space called out">

</div>

## Why this exists

I kept reaching for DaisyDisk and GrandPerspective to figure out where my disk
went, and they're both fine tools. But DaisyDisk costs money for what is, at the
end of the day, a filesystem walk and a chart — and I never felt great about
paying for that. The bigger thing, though: most of these tools stop at "here's a
big folder." They don't know that the 40 GB of `node_modules`, Xcode
`DerivedData`, and assorted caches scattered across your machine are *safe to
delete* and will regenerate themselves. That's the stuff actually filling up a
developer's disk, and nobody was pointing at it.

So I wrote Halo for myself, and figured I'd put it out there. It's free, it's
native, and the source is right here. If something's wrong or missing, please
[open an issue or a PR](https://github.com/amir20/Halo.app/issues) — that's
genuinely welcome.

## What it does

Point it at a folder and it walks the whole tree, works out what's eating the
space, and draws the result as an interactive donut. You can read the same data
two ways — the folders sitting directly inside wherever you've drilled to, or
everything rolled up by file type — and the sidebar stays in sync as you hover
and dig in. It calls out the reclaimable junk a developer's disk tends to fill up
with — `node_modules`, caches, `DerivedData`, the Trash — and tells you roughly
how much you'd get back.

Underneath is **DiskKit**, a dependency-free library that does the filesystem
walk and hands back a classified directory tree. The app is just a view on top
of it.

## Install

Grab the latest `Halo.dmg` from the
[releases page](https://github.com/amir20/Halo.app/releases/latest), drag it to
Applications, and you're done — it auto-updates from there. Or build it yourself
below.

## Requirements

- macOS 26 or newer
- A Swift 6.2 toolchain (ships with Xcode 26)

It's a plain SwiftPM package with no third-party dependencies, built in Swift 6
language mode with strict data-race checking.

## Building

Everything goes through the `Makefile`; run `make` on its own for the full list.

```sh
make run     # build and launch from source
make app     # Halo.app — double-clickable, ad-hoc signed
make dmg     # Halo.dmg — drag-to-install disk image
make test    # run the tests
make icon    # rebuild the app icon from Icons/make-icon.swift
```

`make app` wraps the release binary into a `.app` using the `bundle-app` SwiftPM
plugin, which writes the Info.plist, copies the icon, and ad-hoc signs the
result. CI runs the same steps on every push and uploads `Halo.dmg`.

## How it works

`DiskKit.TreeScanner` walks the tree with raw
POSIX calls (`opendir`, `readdir`, `lstat`) rather than `FileManager`, spreading
the work across a pool of workers that all pull from one shared, depth-first
queue. The single shared queue is deliberate: it stops one enormous subtree —
`~/Library`, a runaway `node_modules` — from starving the rest of the scan.
Sizes are real disk usage (allocated blocks), and symlinks aren't followed.

As directories come back, every file is sorted into a category — dependencies,
caches, build output, media, code, and a handful of others — and directories
that are safe to regenerate get flagged reclaimable. The donut then renders that
two ways: "by folder" shows the children of the current directory, "by type"
rolls every file up by its category. Both stay tied to the sidebar.

Scanning is streamed rather than batched, so the ring appears right away and each
top-level subtree fills in the moment it finishes, with a live file and byte
count running the whole time.

There's a longer write-up of the design in [docs/halo.md](docs/halo.md).

## Layout

| Path | What's there |
| --- | --- |
| `Sources/Halo/` | The SwiftUI app: donut, sidebar, scan model. |
| `Sources/DiskKit/` | The scan library: parallel walk, classified tree, formatting. |
| `Tests/` | Unit tests for both targets. |
| `Plugins/BundleApp/` | The `bundle-app` plugin that builds the `.app`. |
| `Icons/` | The app icon and the Swift program that generates it. |

If you'd rather skip the Makefile, plain `swift build` and `swift test` work too.

## Contributing

Issues and pull requests are welcome — bug reports, misclassified files, a
category that should be flagged reclaimable but isn't, or just an idea. The GUI
can't be tested headlessly (it's a SwiftUI `App`), so anything UI-related needs a
human running it, but the scan engine and model logic in `DiskKit` and `ScanModel`
have unit tests; `swift test` should pass before you open a PR. If you're not sure
where something lives, the [design write-up](docs/halo.md) is a good place to
start.

## Automation

CI (`.github/workflows/ci.yml`) builds and tests on every push and PR and uploads
`Halo.dmg`; tagging `v*` notarizes the DMG and publishes the Sparkle appcast.
[Renovate](https://docs.renovatebot.com/) keeps the pinned Action versions
current, and [Claude](https://github.com/anthropics/claude-code-action) reviews
each pull request and answers `@claude` mentions.
