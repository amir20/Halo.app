import SwiftUI
import DiskKit

struct DonutView: View {
    @Bindable var model: ScanModel
    @State private var swept = false

    // Geometry from the design (460-pt coordinate space, center 230,230).
    private let side: CGFloat = 460
    private let r0: CGFloat = 122     // inner
    private let r1: CGFloat = 196     // outer
    private let rc0: CGFloat = 200    // amber inner
    private let rc1: CGFloat = 207    // amber outer

    var body: some View {
        ZStack {
            // background ring track
            Circle()
                .stroke(Palette.line2, lineWidth: r1 - r0)
                .frame(width: r0 + r1, height: r0 + r1)

            ForEach(model.arcs) { arc in
                slice(arc)
            }

            hole
        }
        .frame(width: side, height: side)
        .animation(.easeOut(duration: 0.18), value: model.hover)
        .animation(.easeOut(duration: 0.18), value: model.expanded)
        .onChange(of: model.sweepKey) { _, _ in restartSweep() }
        .onAppear { restartSweep() }
    }

    private func restartSweep() {
        swept = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.8)) { swept = true }
        }
    }

    @ViewBuilder
    private func slice(_ arc: Arc) -> some View {
        let a0 = arc.a0 + arc.gap / 2
        let a1Full = max(a0 + 0.002, arc.a1 - arc.gap / 2)
        let isHover = model.hover == arc.seg.id
            || (model.mode == .type && model.expanded == arc.seg.category)
        let dimmed = (model.hover != nil || model.expanded != nil) && !isHover
        let outer = isHover ? r1 + 9 : r1
        let end = swept ? a1Full : a0
        let recFrac = arc.seg.size > 0
            ? min(max(Double(arc.seg.recl) / Double(arc.seg.size), 0), 1) : 0
        let base = ArcShape(innerRadius: r0, outerRadius: r1,
                            startAngle: a0, endAngle: a1Full)   // full wedge for hit-testing

        ZStack {
            ArcShape(innerRadius: r0, outerRadius: outer, startAngle: a0, endAngle: end)
                .fill(Palette.color(arc.seg.category))
            ArcShape(innerRadius: r0, outerRadius: outer, startAngle: a0, endAngle: end)
                .stroke(Palette.bg, lineWidth: 2)
            if recFrac > 0.001 {
                ArcShape(innerRadius: rc0, outerRadius: rc1,
                         startAngle: a0,
                         endAngle: swept ? a0 + (a1Full - a0) * recFrac : a0)
                    .fill(Palette.reclaim)
            }
        }
        .opacity(dimmed ? 0.32 : 1)
        .contentShape(base)
        .onHover { inside in
            if inside { model.hover = arc.seg.id }
            else if model.hover == arc.seg.id { model.hover = nil }
        }
        .onTapGesture { model.tapSegment(arc.seg) }
    }

    private var hole: some View {
        let f = model.focus
        let scope = model.displayName(model.current?.name ?? "~")
        let scanning = model.scanning && f == nil
        let name = f?.label ?? scope
        let size = scanning ? model.liveBytes : (f?.size ?? model.total)
        let recl = scanning ? 0 : (f?.recl ?? model.reclTotal)
        let subtitle: String = {
            if scanning { return "scanning… \(model.liveFiles.formatted()) files" }
            if let f { return "\(percent(f.size, of: model.total).clean)% of \(scope)" }
            if model.mode == .type { return "by type · in \(scope)" }
            return model.path.count == 1 ? "used on Macintosh HD" : "in this folder"
        }()

        return ZStack {
            Circle().fill(Palette.bg).frame(width: (r0 - 6) * 2, height: (r0 - 6) * 2)
            VStack(spacing: 3) {
                Text(name.count > 18 ? name.prefix(17) + "…" : name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(f != nil ? Palette.ink2 : Palette.ink3)
                Text(formatSize(size))
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink4)
                if recl > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.reclaim).frame(width: 8, height: 8)
                        Text("\(formatSize(recl)) reclaimable")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.reclaim)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(width: (r0 - 10) * 2)
        }
    }
}

extension Double {
    /// Drops a trailing `.0` so "12.0%" prints as "12%".
    var clean: String {
        self == rounded() ? String(Int(self)) : String(self)
    }
}
