import SwiftUI

@ViewBuilder
func exposeCardThumb(_ item: ExposeWindowItem, w: CGFloat, h: CGFloat, hov: Bool) -> some View {
    Group {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(winMuxOverlayComponentBackground(.normal))
                .overlay(
                    Image(systemName: "macwindow")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(winMuxOverlayContent(.secondary))
                )
        }
    }
    .frame(width: w, height: h)
}
