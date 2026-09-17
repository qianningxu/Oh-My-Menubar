import AppKit

struct ResizePreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> ResizePreviewCornerRadii {
        ResizePreviewCornerRadii(
            topLeft: radius,
            topRight: radius,
            bottomRight: radius,
            bottomLeft: radius
        )
    }
}

func windowResizePreviewCornerRadius(for rect: CGRect) -> CGFloat {
    let minimumDimension = min(rect.width, rect.height)
    guard minimumDimension > 0 else { return 0 }
    return min(min(max(minimumDimension * 0.045, 10), 18), minimumDimension / 2)
}
