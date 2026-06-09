import SwiftUI

struct HeaderView: View {
    @Bindable var model: ScanModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: model.back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 7).stroke(Palette.line))
            .disabled(model.path.count <= 1)
            .opacity(model.path.count <= 1 ? 0.36 : 1)

            crumbs

            Spacer(minLength: 12)

            segmented
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }

    private var crumbs: some View {
        HStack(spacing: 5) {
            ForEach(Array(model.crumbs.enumerated()), id: \.offset) { i, c in
                let last = i == model.crumbs.count - 1
                Text(c)
                    .font(.system(size: 13, weight: last ? .semibold : .medium,
                                  design: i > 0 ? .monospaced : .default))
                    .foregroundStyle(last ? Palette.ink : Palette.ink3)
                    .onTapGesture { if !last && i > 0 { model.goTo(crumb: i - 1) } }
                if !last {
                    Text("›").font(.system(size: 12)).foregroundStyle(Palette.ink4)
                }
            }
        }
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            segButton("By folder", .folder)
            segButton("By type", .type)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.bg3))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line))
    }

    private func segButton(_ title: String, _ lens: Lens) -> some View {
        let on = model.mode == lens
        return Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(on ? Palette.ink : Palette.ink3)
            .padding(.horizontal, 13).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(on ? Palette.bg : Color.clear)
                    .shadow(color: on ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { model.setMode(lens) }
    }
}
