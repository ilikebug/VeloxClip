import SwiftUI

struct ImagePreviewLayoutPolicy: Equatable {
    let scrollAxes: Axis.Set
    let defaultZoomLevel: CGFloat
    let maximumZoomLevel: CGFloat
    let fitsImageToAvailablePanel: Bool

    static let detailImage = ImagePreviewLayoutPolicy(
        scrollAxes: .vertical,
        defaultZoomLevel: 1.0,
        maximumZoomLevel: 1.0,
        fitsImageToAvailablePanel: true
    )
}
