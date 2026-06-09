# Halo — architecture

A native SwiftUI re-implementation of the `Dial.html` design: a clean light
donut disk visualizer built on the project's POSIX scanner. It scans a real
directory tree, classifies it, and renders an interactive donut with two lenses
(**by folder** and **by type**) plus a synced sidebar.

## Components & data flow

```mermaid
flowchart TD
    subgraph App["Halo · SwiftUI app"]
        direction TB
        APP["HaloApp\n@main · scans ~ on launch"]
        CV["ContentView"]
        HV["HeaderView\nbreadcrumbs · By folder / By type"]
        DV["DonutView\nring · amber arcs · live hole"]
        RV["RailView\nrows · type→locations · Reclaim (disabled)"]
        ARC["ArcShape\nanimatable donut wedge"]
        PAL["Palette\noklch → sRGB"]
        MODEL["ScanModel\n@Observable @MainActor\nsegments · arcs · navigation · live counts"]

        APP --> CV
        CV --> HV & DV & RV
        DV --> ARC & PAL
        RV --> PAL
        HV -- "back / drill / setMode" --> MODEL
        DV -- "hover / tap slice" --> MODEL
        RV -- "hover / expand / jump" --> MODEL
        MODEL -- "arcs + focus" --> DV
        MODEL -- "segments + locations" --> RV
        MODEL -- "crumbs + mode" --> HV
    end

    subgraph Kit["DiskKit · library (shared with the CLI)"]
        direction TB
        TS["TreeScanner\nscan / scanStreaming"]
        CLS["Classifier\ndir + extension rules"]
        DN["DirNode\nclassified directory tree"]
        DRV["Derive\nfolder/type lenses · reclaimable"]
        SP["ScanProgress\nMutex-backed live counter"]
        FMT["formatSize / percent"]

        TS --> CLS
        TS --> DN
        TS --> SP
        DRV --> DN
    end

    MODEL == "Task.detached\nscanStreaming(~)" ==> TS
    TS -. "onRoot · onChild · onDone\n(hop to MainActor)" .-> MODEL
    SP -. "poll every 0.1s" .-> MODEL
    MODEL --> DRV
    DV --> FMT
    RV --> FMT

    FS[("Home folder\n~ on disk")] -. "opendir / lstat\nsymlinks skipped" .-> TS
```

## Streaming scan sequence

A full home-folder walk takes a long time (a large `~` is minutes), so the UI
never waits for completion — it renders immediately and fills in as top-level
subtrees finish, with a live counter throughout.

```mermaid
sequenceDiagram
    participant U as User
    participant App as HaloApp
    participant M as ScanModel (MainActor)
    participant T as TreeScanner (bg thread)
    participant P as ScanProgress (Mutex)

    U->>App: launch
    App->>M: scan(~)
    M->>P: create + start 0.1s poll timer
    M->>T: Task.detached scanStreaming(~)
    T->>M: onRoot(root + placeholder children)
    M-->>U: donut appears immediately (empty ring)
    loop each top-level subtree, concurrently
        T->>P: add(files, bytes) while walking
        P-->>M: poll → live counter ticks up
        T->>M: onChild(i, builtSubtree)
        M-->>U: slice grows in (animated rebalance)
    end
    T->>M: onDone()
    M-->>U: final totals · sweep settles
```

## Key decisions

- **Donut by `Canvas`/`Shape`, not Swift Charts** — Charts can't draw the
  per-slice amber *reclaimable* overhang; `ArcShape` reproduces the design's
  exact arc geometry and animates the sweep + hover lift.
- **Directory-only tree** — files are aggregated per directory by category
  (`DirNode.fileBytes`) rather than one node per file, so a whole-home scan
  stays tractable in memory.
- **Override categories** — a reclaimable directory (`node_modules`, `Caches`,
  `DerivedData`, `.Trash`) attributes its whole subtree to its category, so the
  *by type* lens answers "where is all my X?" correctly.
- **Visualize-only** — reclaimable space is shown (amber arcs, "free" tags), but
  the Reclaim button is intentionally disabled; nothing is deleted.
- **Real macOS window chrome** — the design's mock traffic-light titlebar is the
  real window; the app uses a hidden title bar.
