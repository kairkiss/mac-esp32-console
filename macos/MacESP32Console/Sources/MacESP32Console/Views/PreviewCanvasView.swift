import AppKit
import SwiftUI

struct PreviewCanvasView: View {
    let image: NSImage

    var body: some View {
        GroupBox {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.black)
                    .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(2, contentMode: .fit)
                    .padding(22)
            }
            .padding(14)
            .frame(minHeight: 270)
        }
    }
}
